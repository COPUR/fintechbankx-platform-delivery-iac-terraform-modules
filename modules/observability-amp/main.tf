# Amazon Managed Service for Prometheus workspace (remote-write target for the
# in-cluster Prometheus/OTel collector in fintechbankx-platform-observability-sre-operations)
# plus an optional Amazon Managed Grafana workspace. A managed policy for
# remote write and one for query are exported for IRSA roles.

data "aws_partition" "current" {}

locals {
  tags = merge({ ManagedBy = "terraform", Module = "observability-amp" }, var.tags)
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_prometheus_workspace" "this" {
  alias       = var.name
  kms_key_arn = var.kms_key_arn
  tags        = local.tags

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }
}

resource "aws_prometheus_alert_manager_definition" "this" {
  count        = var.alertmanager_definition == null ? 0 : 1
  workspace_id = aws_prometheus_workspace.this.id
  definition   = var.alertmanager_definition
}

resource "aws_prometheus_rule_group_namespace" "this" {
  for_each     = var.rule_group_namespaces
  name         = each.key
  workspace_id = aws_prometheus_workspace.this.id
  data         = each.value
}

data "aws_iam_policy_document" "remote_write" {
  statement {
    actions   = ["aps:RemoteWrite"]
    resources = [aws_prometheus_workspace.this.arn]
  }
}

resource "aws_iam_policy" "remote_write" {
  name        = "${var.name}-amp-remote-write"
  description = "Remote write to AMP workspace ${var.name}"
  policy      = data.aws_iam_policy_document.remote_write.json
  tags        = local.tags
}

data "aws_iam_policy_document" "query" {
  statement {
    actions = [
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata",
    ]
    resources = [aws_prometheus_workspace.this.arn]
  }
}

resource "aws_iam_policy" "query" {
  name        = "${var.name}-amp-query"
  description = "Query AMP workspace ${var.name}"
  policy      = data.aws_iam_policy_document.query.json
  tags        = local.tags
}

# --- Optional Amazon Managed Grafana ---------------------------------------

data "aws_iam_policy_document" "grafana_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  count              = var.enable_grafana ? 1 : 0
  name               = "${var.name}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "grafana_query" {
  count      = var.enable_grafana ? 1 : 0
  role       = aws_iam_role.grafana[0].name
  policy_arn = aws_iam_policy.query.arn
}

resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  count      = var.enable_grafana ? 1 : 0
  role       = aws_iam_role.grafana[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_grafana_workspace" "this" {
  count                    = var.enable_grafana ? 1 : 0
  name                     = var.name
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = var.grafana_authentication_providers
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]
  grafana_version          = var.grafana_version
  tags                     = local.tags
}
