# Baseline AWS resources every FinTechBankX service gets: a CloudWatch log
# group, SSM configuration pointers, a runtime bootstrap secret, a workload
# IAM role (ECS task principal or EKS IRSA) and a managed least-privilege
# policy that grants read access to exactly those SSM parameters and secret.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.environment}-${var.service_slug}"
  common_tags = merge({
    ManagedBy   = "terraform"
    Module      = "microservice-base"
    ServiceName = var.service_name
    ServiceSlug = var.service_slug
    Environment = var.environment
  }, var.tags)

  parameter_root = "${var.parameter_prefix}/${var.environment}/${var.service_slug}"

  # Log group follows the parameter prefix unless a caller pins it. With the
  # default prefix the name is unchanged: /openfinance/<env>/<slug>.
  log_group_root = var.log_group_prefix != null ? var.log_group_prefix : var.parameter_prefix

  use_irsa = var.eks_oidc_provider_arn != null

  ssm_parameter_arn_root = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_root}"
}

resource "aws_cloudwatch_log_group" "service" {
  name              = "${local.log_group_root}/${var.environment}/${var.service_slug}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_group_kms_key_arn
  tags              = local.common_tags
}

resource "aws_ssm_parameter" "database_engine" {
  name        = "${local.parameter_root}/database_engine"
  description = "Database engine for ${var.service_name}"
  type        = "String"
  value       = var.database_engine
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "cache_engine" {
  name        = "${local.parameter_root}/cache_engine"
  description = "Cache engine for ${var.service_name}"
  type        = "String"
  value       = var.cache_engine
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "identity_provider_url" {
  name        = "${local.parameter_root}/identity_provider_url"
  description = "Identity provider URL for ${var.service_name}"
  type        = "String"
  value       = var.identity_provider_url
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "observability_endpoint" {
  name        = "${local.parameter_root}/observability_endpoint"
  description = "Observability endpoint for ${var.service_name}"
  type        = "String"
  value       = var.observability_endpoint
  tags        = local.common_tags
}

resource "random_password" "bootstrap_secret" {
  length  = 40
  special = true
}

resource "aws_secretsmanager_secret" "service_runtime" {
  name                    = var.runtime_secret_name != null ? var.runtime_secret_name : "${var.environment}/${var.service_slug}/runtime"
  description             = "Runtime bootstrap secret for ${var.service_name}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "service_runtime" {
  secret_id = aws_secretsmanager_secret.service_runtime.id
  # Deterministic value (no timestamp()): Terraform sets it once. Rotation is
  # owned by Secrets Manager, so later value changes are not Terraform drift.
  secret_string = jsonencode({
    token = random_password.bootstrap_secret.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# --- Workload identity ------------------------------------------------------

data "aws_iam_policy_document" "workload_assume_role" {
  dynamic "statement" {
    for_each = local.use_irsa ? [] : [1]
    content {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "Service"
        identifiers = [var.workload_principal]
      }
    }
  }

  dynamic "statement" {
    for_each = local.use_irsa ? [1] : []
    content {
      actions = ["sts:AssumeRoleWithWebIdentity"]
      principals {
        type        = "Federated"
        identifiers = [var.eks_oidc_provider_arn]
      }
      condition {
        test     = "StringEquals"
        variable = "${local.oidc_issuer}:sub"
        values   = ["system:serviceaccount:${coalesce(var.kubernetes_namespace, "unset")}:${coalesce(var.kubernetes_service_account, "unset")}"]
      }
      condition {
        test     = "StringEquals"
        variable = "${local.oidc_issuer}:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
}

locals {
  oidc_issuer = var.eks_oidc_provider_url == null ? "" : trimprefix(var.eks_oidc_provider_url, "https://")
}

resource "aws_iam_role" "workload" {
  name                 = "${local.name_prefix}-workload-role"
  assume_role_policy   = data.aws_iam_policy_document.workload_assume_role.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = local.common_tags

  lifecycle {
    precondition {
      condition = !local.use_irsa || (
        var.eks_oidc_provider_url != null &&
        var.kubernetes_namespace != null &&
        var.kubernetes_service_account != null
      )
      error_message = "IRSA needs eks_oidc_provider_url, kubernetes_namespace and kubernetes_service_account when eks_oidc_provider_arn is set."
    }
  }
}

# --- Runtime access policy (own SSM path + own runtime secret) -------------

data "aws_iam_policy_document" "runtime_access" {
  statement {
    sid       = "ReadOwnParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.ssm_parameter_arn_root, "${local.ssm_parameter_arn_root}/*"]
  }

  statement {
    sid       = "ReadOwnRuntimeSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.service_runtime.arn]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [1]
    content {
      sid       = "DecryptRuntimeSecret"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_policy" "runtime_access" {
  name        = "${local.name_prefix}-runtime-access"
  description = "Read ${local.parameter_root}/* and the runtime secret of ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.runtime_access.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "runtime_access" {
  count      = var.attach_runtime_access_policy ? 1 : 0
  role       = aws_iam_role.workload.name
  policy_arn = aws_iam_policy.runtime_access.arn
}
