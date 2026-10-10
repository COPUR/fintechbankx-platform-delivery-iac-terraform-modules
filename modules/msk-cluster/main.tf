# Amazon MSK (provisioned) for the FinTechBankX event backbone:
#  - brokers spread evenly over the private subnets (one AZ each)
#  - TLS only between clients and brokers and inside the cluster
#  - IAM client authentication (SASL/AWS_MSK_IAM, port 9098); no plaintext,
#    no unauthenticated access
#  - KMS encryption at rest with a dedicated key
#  - topics are created explicitly (auto.create.topics.enable=false) by the
#    event-streaming repo; defaults RF 3 / min.insync.replicas 2
#  - broker logs in CloudWatch, Prometheus JMX/node exporters for scraping

locals {
  tags        = merge({ ManagedBy = "terraform", Module = "msk-cluster", Cluster = var.cluster_name }, var.observability_discovery ? { "fintechbankx.io/observability" = "enabled" } : {}, var.tags)
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn

  server_properties = merge({
    "auto.create.topics.enable"      = "false"
    "default.replication.factor"     = "3"
    "min.insync.replicas"            = "2"
    "num.partitions"                 = "6"
    "unclean.leader.election.enable" = "false"
    "allow.everyone.if.no.acl.found" = "false"
    "log.retention.hours"            = "168"
    "num.io.threads"                 = "8"
    "num.network.threads"            = "5"
    "num.replica.fetchers"           = "2"
    "replica.lag.time.max.ms"        = "30000"
    "socket.request.max.bytes"       = "104857600"
  }, var.server_properties_overrides)
}

resource "aws_kms_key" "this" {
  count                   = var.kms_key_arn == null ? 1 : 0
  description             = "MSK ${var.cluster_name} encryption at rest"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count         = var.kms_key_arn == null ? 1 : 0
  name          = "alias/msk/${var.cluster_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_security_group" "this" {
  name        = "${var.cluster_name}-msk"
  description = "MSK brokers for ${var.cluster_name}: IAM/TLS clients only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.cluster_name}-msk" })
}

resource "aws_vpc_security_group_ingress_rule" "iam_tls" {
  count                        = length(var.client_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.client_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 9098
  to_port                      = 9098
  description                  = "Kafka SASL/IAM over TLS from client security group ${count.index}"
}

# Brokers replicate to each other inside the same security group.
resource "aws_vpc_security_group_ingress_rule" "self" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "-1"
  description                  = "Broker to broker"
}

resource "aws_vpc_security_group_egress_rule" "self" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "-1"
  description                  = "Broker to broker"
}

resource "aws_vpc_security_group_ingress_rule" "prometheus" {
  count                        = var.enable_open_monitoring ? length(var.monitoring_security_group_ids) : 0
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.monitoring_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 11001
  to_port                      = 11002
  description                  = "Prometheus JMX and node exporters"
}

resource "aws_msk_configuration" "this" {
  name              = "${var.cluster_name}-config"
  kafka_versions    = [var.kafka_version]
  description       = "FinTechBankX broker defaults: explicit topics, RF 3, min ISR 2"
  server_properties = join("\n", [for k in sort(keys(local.server_properties)) : "${k}=${local.server_properties[k]}"])

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "broker" {
  name              = "/aws/msk/${var.cluster_name}/broker"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_group_kms_key_arn
  tags              = local.tags
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes
  enhanced_monitoring    = var.enhanced_monitoring

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.this.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size_gb

        dynamic "provisioned_throughput" {
          for_each = var.provisioned_throughput_mibps == null ? [] : [1]
          content {
            enabled           = true
            volume_throughput = var.provisioned_throughput_mibps
          }
        }
      }
    }

    connectivity_info {
      public_access {
        type = "DISABLED"
      }
    }
  }

  client_authentication {
    unauthenticated = false
    sasl {
      iam   = true
      scram = false
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = local.kms_key_arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = var.enable_open_monitoring
      }
      node_exporter {
        enabled_in_broker = var.enable_open_monitoring
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.broker.name
      }
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.number_of_broker_nodes % length(var.subnet_ids) == 0
      error_message = "number_of_broker_nodes must be a multiple of the number of subnets (one AZ per subnet)."
    }
  }
}

# --- Alarms -----------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "under_replicated" {
  alarm_name          = "${var.cluster_name}-under-replicated-partitions"
  alarm_description   = "Partitions are under-replicated; with min.insync.replicas=2 producers using acks=all will fail if this persists."
  namespace           = "AWS/Kafka"
  metric_name         = "UnderReplicatedPartitions"
  dimensions          = { "Cluster Name" = aws_msk_cluster.this.cluster_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "active_controller" {
  alarm_name          = "${var.cluster_name}-active-controller"
  alarm_description   = "Exactly one active controller is expected."
  namespace           = "AWS/Kafka"
  metric_name         = "ActiveControllerCount"
  dimensions          = { "Cluster Name" = aws_msk_cluster.this.cluster_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
  tags                = local.tags
}

# --- Topic administration -----------------------------------------------------
# For the provisioning job of fintechbankx-platform-event-streaming-kafka
# (scripts/kafka/create-topics.sh). Services never get these actions.

locals {
  topic_arn_root = replace(aws_msk_cluster.this.arn, ":cluster/", ":topic/")
}

data "aws_iam_policy_document" "topic_admin" {
  statement {
    sid       = "ConnectToCluster"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [aws_msk_cluster.this.arn]
  }

  statement {
    sid = "ManageCatalogTopics"
    actions = [
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:AlterTopic",
      "kafka-cluster:DescribeTopicDynamicConfiguration",
      "kafka-cluster:AlterTopicDynamicConfiguration",
    ]
    resources = [for p in var.topic_admin_prefixes : "${local.topic_arn_root}/${p}*"]
  }
}

resource "aws_iam_policy" "topic_admin" {
  count       = var.create_topic_admin_policy ? 1 : 0
  name        = "${var.cluster_name}-topic-admin"
  description = "Create and alter catalog topics on ${var.cluster_name} (no delete)"
  policy      = data.aws_iam_policy_document.topic_admin.json
  tags        = local.tags
}
