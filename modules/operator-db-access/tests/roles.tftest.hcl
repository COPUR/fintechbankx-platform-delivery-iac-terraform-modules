# Offline (mock provider): one operator role per service, assumable only by
# the listed principals (Identity Center permission-set roles), reading only
# <env>/<slug>/db-import and decrypting only through Secrets Manager for that
# secret.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "me-central-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  environment            = "dev"
  service_slugs          = ["payment-request-to-pay-service", "loan-lifecycle-service"]
  trusted_principal_arns = ["arn:aws:iam::111122223333:role/aws-reserved/sso.amazonaws.com/me-central-1/AWSReservedSSO_DbOperator_0123456789abcdef"]
}

run "one_role_per_service" {
  command = plan

  assert {
    condition     = toset(keys(aws_iam_role.this)) == toset(["payment-request-to-pay-service", "loan-lifecycle-service"])
    error_message = "One role per service slug."
  }

  assert {
    condition     = aws_iam_role.this["payment-request-to-pay-service"].name == "dev-payment-request-to-pay-service-db-import"
    error_message = "Role name <env>-<slug>-db-import."
  }
}

run "trust_only_listed_principals" {
  command = plan

  assert {
    condition     = toset(flatten([for p in one(data.aws_iam_policy_document.trust.statement).principals : tolist(p.identifiers)])) == toset(["arn:aws:iam::111122223333:role/aws-reserved/sso.amazonaws.com/me-central-1/AWSReservedSSO_DbOperator_0123456789abcdef"])
    error_message = "Only the listed principal ARNs may assume the roles."
  }
}

run "secret_read_only_db_import" {
  command = plan

  assert {
    condition     = [for s in data.aws_iam_policy_document.access["payment-request-to-pay-service"].statement : s.actions if s.sid == "ReadDbImportSecret"][0] == toset(["secretsmanager:GetSecretValue"])
    error_message = "Only secretsmanager:GetSecretValue."
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.access["payment-request-to-pay-service"].statement : s.resources if s.sid == "ReadDbImportSecret"][0] == toset(["arn:aws:secretsmanager:me-central-1:111122223333:secret:dev/payment-request-to-pay-service/db-import-??????"])
    error_message = "Only <env>/<slug>/db-import (random 6-character suffix)."
  }
}

run "kms_decrypt_only_via_secrets_manager_for_that_secret" {
  command = plan

  assert {
    condition     = [for s in data.aws_iam_policy_document.access["loan-lifecycle-service"].statement : s.actions if s.sid == "DecryptDbImportSecret"][0] == toset(["kms:Decrypt"])
    error_message = "Only kms:Decrypt."
  }

  assert {
    condition = toset(flatten([for s in data.aws_iam_policy_document.access["loan-lifecycle-service"].statement : [for c in s.condition : "${c.test}|${c.variable}|${join(",", c.values)}"] if s.sid == "DecryptDbImportSecret"])) == toset([
      "StringEquals|kms:ViaService|secretsmanager.me-central-1.amazonaws.com",
      "StringLike|kms:EncryptionContext:SecretARN|arn:aws:secretsmanager:me-central-1:111122223333:secret:dev/loan-lifecycle-service/db-import-??????",
    ])
    error_message = "kms:Decrypt only via Secrets Manager with the SecretARN encryption context of that secret."
  }
}

run "wildcard_principal_rejected" {
  command = plan

  variables {
    trusted_principal_arns = ["*"]
  }

  expect_failures = [var.trusted_principal_arns]
}

run "bad_slug_rejected" {
  command = plan

  variables {
    service_slugs = ["Payment Service"]
  }

  expect_failures = [var.service_slugs]
}

run "creates_empty_db_import_secret_containers" {
  command = plan

  variables {
    kms_key_arns = { "payment-request-to-pay-service" = "arn:aws:kms:me-central-1:111122223333:key/11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_secretsmanager_secret.db_import["payment-request-to-pay-service"].name == "dev/payment-request-to-pay-service/db-import"
    error_message = "Secret container <env>/<slug>/db-import per service."
  }

  assert {
    condition     = aws_secretsmanager_secret.db_import["payment-request-to-pay-service"].kms_key_id == "arn:aws:kms:me-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
    error_message = "Encrypted with the service's secrets key when one is given."
  }

  assert {
    condition     = aws_secretsmanager_secret.db_import["payment-request-to-pay-service"].tags["fintechbankx.io/value-in-state"] == "false" && !contains(keys(aws_secretsmanager_secret.db_import["payment-request-to-pay-service"].tags), "fintechbankx.io/secrets")
    error_message = "Operator-filled (value-in-state=false) and not an External Secrets source."
  }
}

run "secret_containers_optional" {
  command = plan

  variables {
    create_db_import_secrets = false
  }

  assert {
    condition     = length(aws_secretsmanager_secret.db_import) == 0
    error_message = "create_db_import_secrets=false creates no containers."
  }
}
