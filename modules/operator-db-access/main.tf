# Per-service operator roles for database imports. Each role may read only
# the secret <env>/<slug>/db-import (credential an operator uses from the
# operator host) and decrypt it only through Secrets Manager for that secret
# (kms:ViaService + encryption context SecretARN). The roles are assumed by
# existing principals, normally IAM Identity Center permission-set roles; this
# module creates no permission set or user. Sessions must carry a source
# identity (sts:SourceIdentity).

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  secret_arn_pattern = {
    for s in var.service_slugs : s =>
    "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.environment}/${s}/db-import-??????"
  }
}

# Every session must name the person: the caller passes --source-identity
# (normally the Identity Center user name); it is recorded in CloudTrail for
# the AssumeRole and every call made with the session, and survives role
# chaining. AssumeRole without a source identity is refused.
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "OperatorPrincipalsWithSourceIdentity"
    actions = ["sts:AssumeRole", "sts:SetSourceIdentity"]
    principals {
      type        = "AWS"
      identifiers = var.trusted_principal_arns
    }
    condition {
      test     = "StringLike"
      variable = "sts:SourceIdentity"
      values   = ["*"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = toset(var.service_slugs)

  name                 = "${var.environment}-${each.key}-db-import"
  description          = "Operator access to ${var.environment}/${each.key}/db-import only"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration_seconds
  permissions_boundary = var.permissions_boundary_arn
  tags                 = merge(var.tags, { "fintechbankx.io/service-slug" = each.key })
}

data "aws_iam_policy_document" "access" {
  for_each = toset(var.service_slugs)

  statement {
    sid       = "ReadDbImportSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.secret_arn_pattern[each.key]]
  }

  statement {
    sid       = "DecryptDbImportSecret"
    actions   = ["kms:Decrypt"]
    resources = [lookup(var.kms_key_arns, each.key, "*")]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:SecretARN"
      values   = [local.secret_arn_pattern[each.key]]
    }
  }
}

data "aws_iam_policy_document" "logs" {
  for_each = { for s, a in var.postgresql_log_group_arns : s => trimsuffix(a, ":*") if contains(var.service_slugs, s) }

  statement {
    sid       = "ReadPostgresqlLogGroup"
    actions   = ["logs:DescribeLogStreams", "logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery"]
    resources = [each.value, "${each.value}:*"]
  }

  statement {
    sid       = "ReadQueryResults"
    actions   = ["logs:GetQueryResults", "logs:StopQuery"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  for_each = data.aws_iam_policy_document.logs

  name   = "postgresql-log-read"
  role   = aws_iam_role.this[each.key].id
  policy = each.value.json
}

resource "aws_iam_role_policy" "access" {
  for_each = toset(var.service_slugs)

  name   = "db-import-secret"
  role   = aws_iam_role.this[each.key].id
  policy = data.aws_iam_policy_document.access[each.key].json
}

# Empty containers: the value is written by the owning squad's DBA
# (put-secret-value from a workstation), never by Terraform, so it is not in
# state. Encrypted with the service's ADR-023 secrets key, which is tagged
# fintechbankx.io/secrets=true and therefore usable by the External Secrets
# roles: what keeps the secret out of the cluster is the explicit Deny on
# <env>/*/db-import-?????? in both store roles (external-secrets-irsa,
# DenyOperatorDbImportSecrets), not a tag on the secret.
resource "aws_secretsmanager_secret" "db_import" {
  for_each = var.create_db_import_secrets ? toset(var.service_slugs) : toset([])

  lifecycle {
    # Without a customer managed key the secret falls back to the AWS managed
    # key aws/secretsmanager, which every principal allowed GetSecretValue in
    # the account can use; the kms:Decrypt grant could not be scoped to a key.
    precondition {
      condition     = contains(keys(var.kms_key_arns), each.key)
      error_message = "kms_key_arns must name the ADR-023 secrets key (aurora-postgresql output secrets_kms_key_arn) of every service slug when create_db_import_secrets is true."
    }
  }

  name                    = "${var.environment}/${each.key}/db-import"
  description             = "Operator database import credential for ${each.key}; filled by an operator, read only through ${var.environment}-${each.key}-db-import"
  kms_key_id              = lookup(var.kms_key_arns, each.key, null)
  recovery_window_in_days = var.recovery_window_in_days
  tags = merge(var.tags, {
    "fintechbankx.io/service-slug"   = each.key
    "fintechbankx.io/value-in-state" = "false"
  })
}
