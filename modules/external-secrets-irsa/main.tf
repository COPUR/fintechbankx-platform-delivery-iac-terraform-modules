# IRSA roles for External Secrets Operator (contract addendum 2026-10-08,
# security review 2026-10-08). Two read-only roles, one per ClusterSecretStore:
#  - service store "aws-secrets-manager": service account
#    external-secrets/external-secrets; reads <env>/* except the platform and
#    identity prefixes (explicit Deny on <env>/platform/*,
#    <env>/identity-keycloak/*, <env>/identity-openldap/*).
#  - platform store "aws-secrets-manager-platform": service account
#    external-secrets/external-secrets-platform (token-only); reads those
#    prefixes plus <env>/*/oidc-client (the Keycloak realm import sets every
#    client secret).
# Both decrypt only through Secrets Manager with KMS keys tagged
# fintechbankx.io/secrets=true. Neither may write or create secrets, and both
# explicitly deny the operator credentials <env>/<slug>/db-import
# (operator-db-access): they sit inside <env>/* and use the tagged secrets
# key, so only an explicit Deny keeps them out of the cluster.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  secret_arn_root    = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.environment}"
  secret_arn_pattern = "${local.secret_arn_root}/*"

  platform_only_secret_arns = [for p in var.platform_secret_prefixes : "${local.secret_arn_root}/${p}/*"]
  # Secrets Manager appends -<6 random characters> to every secret ARN.
  oidc_client_secret_arn = "${local.secret_arn_root}/*/oidc-client-??????"
  # Operator-only credentials (operator-db-access); never synced into the cluster.
  operator_only_secret_arns = ["${local.secret_arn_root}/*/db-import-??????"]

  kms_key_arns = "arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/*"

  store_roles = merge(
    { service = { namespace = var.namespace, service_account = var.service_account } },
    var.create_platform_role ? { platform = { namespace = var.namespace, service_account = var.platform_service_account } } : {}
  )
}

data "aws_iam_policy_document" "service_store" {
  statement {
    sid       = "ReadEnvironmentSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [local.secret_arn_pattern]
  }

  statement {
    sid       = "DenyPlatformAndIdentitySecrets"
    effect    = "Deny"
    actions   = ["secretsmanager:*"]
    resources = local.platform_only_secret_arns
  }

  statement {
    sid       = "DenyOperatorDbImportSecrets"
    effect    = "Deny"
    actions   = ["secretsmanager:*"]
    resources = local.operator_only_secret_arns
  }

  statement {
    sid       = "DecryptWithTaggedKeysViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arns]

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

data "aws_iam_policy_document" "platform_store" {
  statement {
    sid       = "ReadPlatformIdentityAndClientSecrets"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = concat(local.platform_only_secret_arns, [local.oidc_client_secret_arn])
  }

  statement {
    sid       = "DenyOperatorDbImportSecrets"
    effect    = "Deny"
    actions   = ["secretsmanager:*"]
    resources = local.operator_only_secret_arns
  }

  statement {
    sid       = "DecryptWithTaggedKeysViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arns]

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

# Service store role (address unchanged so existing state keeps the role).
module "role" {
  source = "../irsa-role"

  role_name          = var.role_name != null ? var.role_name : "${var.cluster_name}-external-secrets"
  description        = "External Secrets Operator (ClusterSecretStore aws-secrets-manager) for ${var.environment}"
  oidc_provider_arn  = var.oidc_provider_arn
  oidc_provider_url  = var.oidc_provider_url
  service_accounts   = [{ namespace = local.store_roles["service"].namespace, name = local.store_roles["service"].service_account }]
  inline_policy_json = data.aws_iam_policy_document.service_store.json
  tags               = merge({ ManagedBy = "terraform", Module = "external-secrets-irsa", SecretStore = "aws-secrets-manager" }, var.tags)
}

module "platform_role" {
  source = "../irsa-role"
  count  = var.create_platform_role ? 1 : 0

  role_name          = var.platform_role_name != null ? var.platform_role_name : "${var.cluster_name}-external-secrets-platform"
  description        = "External Secrets Operator (ClusterSecretStore aws-secrets-manager-platform) for ${var.environment}"
  oidc_provider_arn  = var.oidc_provider_arn
  oidc_provider_url  = var.oidc_provider_url
  service_accounts   = [{ namespace = local.store_roles["platform"].namespace, name = local.store_roles["platform"].service_account }]
  inline_policy_json = data.aws_iam_policy_document.platform_store.json
  tags               = merge({ ManagedBy = "terraform", Module = "external-secrets-irsa", SecretStore = "aws-secrets-manager-platform" }, var.tags)
}
