# AWS side of fintechbankx-platform-observability-sre-operations
# (docs/observability/PLATFORM_OBSERVABILITY.md, "AWS resources this repo
# expects"): IRSA roles <cluster>-obs-<sa> for the service accounts in
# namespace observability, SSE-KMS buckets for Tempo and Loki, and a small
# Aurora PostgreSQL database for Grafana. AMP is module.observability;
# Aurora/MSK carry fintechbankx.io/observability=enabled for YACE.

locals {
  obs_buckets = {
    traces      = "${var.name_prefix}-${var.environment}-obs-traces"
    logs-chunks = "${var.name_prefix}-${var.environment}-obs-logs-chunks"
    logs-ruler  = "${var.name_prefix}-${var.environment}-obs-logs-ruler"
  }
  obs_bucket_users = {
    tempo = ["traces"]
    loki  = ["logs-chunks", "logs-ruler"]
  }
}

resource "aws_kms_key" "observability" {
  description             = "${local.name} observability buckets (Tempo, Loki)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags
}

resource "aws_kms_alias" "observability" {
  name          = "alias/${local.name}-observability"
  target_key_id = aws_kms_key.observability.key_id
}

resource "aws_s3_bucket" "observability" {
  for_each = local.obs_buckets
  bucket   = each.value
  tags     = merge(local.tags, { Component = each.key })
}

resource "aws_s3_bucket_public_access_block" "observability" {
  for_each                = aws_s3_bucket.observability
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  for_each = aws_s3_bucket.observability
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.observability.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  for_each = { for k, b in aws_s3_bucket.observability : k => b if k != "logs-ruler" }
  bucket   = each.value.id
  rule {
    id     = "expire-backstop"
    status = "Enabled"
    filter {}
    expiration {
      days = var.observability_log_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "obs_tls_only" {
  for_each = aws_s3_bucket.observability
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "observability" {
  for_each   = aws_s3_bucket.observability
  bucket     = each.value.id
  policy     = data.aws_iam_policy_document.obs_tls_only[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.observability]
}

data "aws_iam_policy_document" "obs_storage" {
  for_each = local.obs_bucket_users

  statement {
    sid       = "ListBuckets"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [for b in each.value : aws_s3_bucket.observability[b].arn]
  }

  statement {
    sid       = "Objects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:GetObjectTagging", "s3:PutObjectTagging"]
    resources = [for b in each.value : "${aws_s3_bucket.observability[b].arn}/*"]
  }

  statement {
    sid       = "BucketKey"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.observability.arn]
  }
}

data "aws_iam_policy_document" "obs_yace" {
  statement {
    sid       = "CloudWatchRead"
    actions   = ["cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "tag:GetResources"]
    resources = ["*"]
  }
}

module "observability_irsa" {
  source = "../../modules/irsa-role"
  for_each = {
    prometheus   = { policy_arns = { amp_remote_write = module.observability.remote_write_policy_arn }, inline = null, attach_inline = false }
    otel-gateway = { policy_arns = { amp_remote_write = module.observability.remote_write_policy_arn }, inline = null, attach_inline = false }
    tempo        = { policy_arns = {}, inline = data.aws_iam_policy_document.obs_storage["tempo"].json, attach_inline = true }
    loki         = { policy_arns = {}, inline = data.aws_iam_policy_document.obs_storage["loki"].json, attach_inline = true }
    yace         = { policy_arns = {}, inline = data.aws_iam_policy_document.obs_yace.json, attach_inline = true }
  }

  role_name          = "${module.eks.cluster_name}-obs-${each.key}"
  description        = "Observability ${each.key} (namespace observability)"
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  service_accounts   = [{ namespace = "observability", name = each.key }]
  policy_arns        = each.value.policy_arns
  inline_policy_json = each.value.inline
  # Known at plan: the tempo/loki JSON references buckets and a key created in
  # the same plan, so the count cannot be derived from it on a first plan.
  attach_inline_policy = each.value.attach_inline
  tags                 = local.tags
}

module "grafana_db" {
  source = "../../modules/aurora-postgresql"
  count  = var.create_grafana_database ? 1 : 0

  name                       = "${local.name}-grafana"
  database_name              = "grafana"
  master_username            = "grafana_admin"
  instance_count             = var.environment == "prod" ? 2 : 1
  min_capacity               = 0.5
  max_capacity               = 2
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  app_secret_name            = "${var.environment}/observability/grafana-db"
  alarm_topic_arn            = var.alarm_topic_arn
  tags                       = merge(local.tags, { Service = "grafana" })
}
