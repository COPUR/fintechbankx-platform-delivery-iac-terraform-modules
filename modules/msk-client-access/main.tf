# Topic-scoped Amazon MSK IAM policy for one service (contract: SASL_SSL with
# AWS_MSK_IAM through the service's IRSA role).
#  - produce: the service's own evt.<ctx>.<aggregate>.* namespaces
#    (produce_topic_prefixes) and exact topics (produce_topics, e.g. the DLQ
#    of another namespace it consumes)
#  - consume: only the listed topics, only with its own consumer groups
#    cg.<service-id>.<purpose>.v<major> (consumer_groups) or the prefix
#    cg.<service-id>. (consumer_group_prefixes)
# Input names follow topics/generated/msk-client-access.json in
# fintechbankx-platform-event-streaming-kafka.
# Topic creation and configuration stay with the event-streaming repo; this
# policy grants no CreateTopic/AlterTopic/DeleteTopic.

locals {
  # arn:<p>:kafka:<r>:<a>:cluster/<name>/<uuid> -> .../topic/<name>/<uuid>
  topic_arn_root = replace(var.cluster_arn, ":cluster/", ":topic/")
  group_arn_root = replace(var.cluster_arn, ":cluster/", ":group/")
  txn_arn_root   = replace(var.cluster_arn, ":cluster/", ":transactional-id/")

  produce_arns = concat(
    [for p in var.produce_topic_prefixes : "${local.topic_arn_root}/${p}*"],
    [for t in var.produce_topics : "${local.topic_arn_root}/${t}"],
  )
  consume_arns = [for t in var.consume_topics : "${local.topic_arn_root}/${t}"]
  group_arns = concat(
    [for g in var.consumer_groups : "${local.group_arn_root}/${g}"],
    [for g in var.consumer_group_prefixes : "${local.group_arn_root}/${g}*"],
  )
  txn_arns = [for t in var.transactional_id_prefixes : "${local.txn_arn_root}/${t}*"]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "ConnectToCluster"
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [var.cluster_arn]
  }

  dynamic "statement" {
    for_each = length(local.produce_arns) > 0 ? [1] : []
    content {
      sid       = "IdempotentProducer"
      actions   = ["kafka-cluster:WriteDataIdempotently"]
      resources = [var.cluster_arn]
    }
  }

  dynamic "statement" {
    for_each = length(local.produce_arns) > 0 ? [1] : []
    content {
      sid       = "ProduceOwnTopics"
      actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData"]
      resources = local.produce_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.consume_arns) > 0 ? [1] : []
    content {
      sid       = "ConsumeListedTopics"
      actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
      resources = local.consume_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.group_arns) > 0 ? [1] : []
    content {
      sid       = "UseOwnConsumerGroups"
      actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
      resources = local.group_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.txn_arns) > 0 ? [1] : []
    content {
      sid       = "UseOwnTransactionalIds"
      actions   = ["kafka-cluster:DescribeTransactionalId", "kafka-cluster:AlterTransactionalId"]
      resources = local.txn_arns
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = "MSK client access for ${var.service_id}"
  policy      = data.aws_iam_policy_document.this.json
  tags        = var.tags

  lifecycle {
    precondition {
      condition     = length(var.consume_topics) == 0 || length(var.consumer_groups) + length(var.consumer_group_prefixes) > 0
      error_message = "A consumer needs consumer_groups or consumer_group_prefixes."
    }
    precondition {
      condition = alltrue([for g in concat(var.consumer_groups, var.consumer_group_prefixes) :
        startswith(g, "cg.${var.service_id}.")
      ])
      error_message = "Consumer groups must belong to the service: cg.<service_id>.<purpose>.v<major> or the prefix cg.<service_id>."
    }
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = toset(var.attach_to_role_names)
  role       = each.value
  policy_arn = aws_iam_policy.this.arn
}
