# IRSA role for External Secrets Operator (contract addendum 2026-10-08):
# service account external-secrets/external-secrets backs the single
# ClusterSecretStore "aws-secrets-manager". It may read only secrets named
# <env>/* in this account and region, and decrypt only through Secrets
# Manager with KMS keys tagged fintechbankx.io/secrets=true.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  secret_arn_pattern = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.environment}/*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid = "ReadEnvironmentSecrets"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = [local.secret_arn_pattern]
  }

  statement {
    sid       = "DecryptWithTaggedKeysViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.kms_key_tag_key}"
      values   = [var.kms_key_tag_value]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

module "role" {
  source = "../irsa-role"

  role_name          = var.role_name != null ? var.role_name : "${var.cluster_name}-external-secrets"
  description        = "External Secrets Operator (ClusterSecretStore aws-secrets-manager) for ${var.environment}"
  oidc_provider_arn  = var.oidc_provider_arn
  oidc_provider_url  = var.oidc_provider_url
  service_accounts   = [{ namespace = var.namespace, name = var.service_account }]
  inline_policy_json = data.aws_iam_policy_document.this.json
  tags               = merge({ ManagedBy = "terraform", Module = "external-secrets-irsa" }, var.tags)
}
