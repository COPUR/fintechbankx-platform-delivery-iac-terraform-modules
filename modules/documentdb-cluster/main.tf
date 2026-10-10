# Amazon DocumentDB cluster owned by exactly one service (open finance data
# services). Instances spread across AZs, KMS encryption at rest, TLS forced
# by the cluster parameter group, audit and profiler logs to CloudWatch, a
# security group that admits only the workload security group(s), backups
# with PITR, and two Secrets Manager entries:
#  - <name>/docdb-master        admin credential for the DBA bootstrap only
#                               (deliberately outside <env>/* so the cluster
#                               secret store cannot sync it)
#  - <env>/<slug>/docdb-app     application credential container; the DBA
#                               bootstrap creates the app user and writes it
# Provider 5.x has no RDS-managed master secret for DocumentDB, so the admin
# credential is generated here and therefore present in (encrypted) state.

locals {
  name = var.name != null ? var.name : "${var.environment}-${var.service_slug}"
  tags = merge({ ManagedBy = "terraform", Module = "documentdb-cluster", Service = var.service_slug }, var.observability_discovery ? { "fintechbankx.io/observability" = "enabled" } : {}, var.tags)
  # ADR-023 KMS split: storage key and secrets key.
  kms_key_arn         = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn
  secrets_kms_key_arn = var.secrets_kms_key_arn != null ? var.secrets_kms_key_arn : aws_kms_key.secrets[0].arn
  alarm               = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
}

# Storage key (cluster storage and snapshots). Not tagged
# fintechbankx.io/secrets: the External Secrets roles cannot use it.
resource "aws_kms_key" "this" {
  count                   = var.kms_key_arn == null ? 1 : 0
  description             = "DocumentDB ${local.name}: storage and snapshots"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count         = var.kms_key_arn == null ? 1 : 0
  name          = "alias/${local.name}-docdb-storage"
  target_key_id = aws_kms_key.this[0].key_id
}

# Secrets key (docdb-master, docdb-app). Tagged so External Secrets can
# decrypt the app credential through Secrets Manager.
resource "aws_kms_key" "secrets" {
  count                   = var.secrets_kms_key_arn == null ? 1 : 0
  description             = "DocumentDB ${local.name}: Secrets Manager credentials"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.tags, { "fintechbankx.io/secrets" = "true" })
}

resource "aws_kms_alias" "secrets" {
  count         = var.secrets_kms_key_arn == null ? 1 : 0
  name          = "alias/${local.name}-docdb-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}

resource "aws_docdb_subnet_group" "this" {
  name       = "${local.name}-docdb"
  subnet_ids = var.subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${local.name}-docdb"
  description = "DocumentDB access for ${local.name} workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-docdb" })
}

resource "aws_vpc_security_group_ingress_rule" "docdb" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
  description                  = "DocumentDB from workload security group ${count.index}"
}

resource "aws_docdb_cluster_parameter_group" "this" {
  name        = "${local.name}-docdb${replace(var.engine_major_version, ".", "")}"
  family      = "docdb${var.engine_major_version}"
  description = "TLS enforced, audit logs on for ${local.name}"
  tags        = local.tags

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "audit_logs"
    value = "enabled"
  }

  parameter {
    name  = "profiler"
    value = "enabled"
  }

  parameter {
    name  = "profiler_threshold_ms"
    value = tostring(var.profiler_threshold_ms)
  }
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "${local.name}/docdb-master"
  description             = "DocumentDB admin credential for ${local.name} (DBA bootstrap only)"
  kms_key_id              = local.secrets_kms_key_arn
  recovery_window_in_days = 7
  # Terraform writes this value, so the tf-plan role may refresh it (github-oidc).
  tags = merge(local.tags, { "fintechbankx.io/value-in-state" = "true" })
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username   = var.master_username
    "password" = random_password.master.result
    host       = aws_docdb_cluster.this.endpoint
    port       = aws_docdb_cluster.this.port
  })

  # Rotation (Secrets Manager rotation Lambda) owns the value after creation.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_docdb_cluster" "this" {
  cluster_identifier              = "${local.name}-docdb"
  engine                          = "docdb"
  engine_version                  = var.engine_version
  master_username                 = var.master_username
  master_password                 = random_password.master.result
  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.this.name
  storage_encrypted               = true
  kms_key_id                      = local.kms_key_arn
  backup_retention_period         = var.backup_retention_days
  preferred_backup_window         = "01:00-02:00"
  preferred_maintenance_window    = "sun:03:00-sun:04:00"
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${local.name}-docdb-final"
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  tags                            = local.tags

  lifecycle {
    # Rotated outside Terraform after bootstrap.
    ignore_changes = [master_password]

    precondition {
      condition     = var.kms_key_arn == null || var.secrets_kms_key_arn == null || var.kms_key_arn != var.secrets_kms_key_arn
      error_message = "kms_key_arn (storage) and secrets_kms_key_arn (secrets) must be different keys (ADR-023)."
    }
  }
}

resource "aws_docdb_cluster_instance" "this" {
  count                      = var.instance_count
  identifier                 = "${local.name}-docdb-${count.index + 1}"
  cluster_identifier         = aws_docdb_cluster.this.id
  instance_class             = var.instance_class
  auto_minor_version_upgrade = true
  promotion_tier             = count.index
  tags                       = local.tags
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.environment}/${var.service_slug}/docdb-app"
  description             = "Application credential for ${local.name} DocumentDB (written by the DBA bootstrap)"
  kms_key_id              = local.secrets_kms_key_arn
  recovery_window_in_days = 7
  tags                    = local.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${local.name}-docdb-cpu-high"
  alarm_description   = "DocumentDB CPU high; scale instance_class or look for unindexed queries (profiler log)."
  namespace           = "AWS/DocDB"
  metric_name         = "CPUUtilization"
  dimensions          = { DBClusterIdentifier = aws_docdb_cluster.this.cluster_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  alarm_name          = "${local.name}-docdb-connections-high"
  alarm_description   = "Connections near the pool budget."
  namespace           = "AWS/DocDB"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBClusterIdentifier = aws_docdb_cluster.this.cluster_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.connections_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm
  tags                = local.tags
}
