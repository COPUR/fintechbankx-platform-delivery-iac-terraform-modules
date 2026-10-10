# Offline (mock provider): ADR-023 KMS split. The storage key (cluster
# storage, snapshots, Performance Insights) is not tagged
# fintechbankx.io/secrets, so the External Secrets roles can never decrypt
# with it; every Secrets Manager secret of the module (RDS-managed master
# secret, db-app, db-migration) is encrypted with the separate secrets key,
# which carries the tag.

mock_provider "aws" {
  mock_resource "aws_rds_cluster" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:me-central-1:111122223333:secret:rds-admin-AbCdEf"
        kms_key_id    = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-0000000000b2"
        secret_status = "active"
      }]
    }
  }
}

override_resource {
  target = aws_kms_key.this
  values = { arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-0000000000a1" }
}

override_resource {
  target = aws_kms_key.secrets
  values = { arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-0000000000b2" }
}

variables {
  name                       = "dev-payment-request-to-pay-service"
  database_name              = "db_pay_request_to_pay_dev"
  master_username            = "rtp_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/payment-request-to-pay-service/db-app"
}

run "storage_and_secrets_keys_are_separate" {
  command = apply

  assert {
    condition     = length(aws_kms_key.this) == 1 && length(aws_kms_key.secrets) == 1
    error_message = "Without overrides the module creates a storage key and a secrets key."
  }

  assert {
    condition     = !contains(keys(aws_kms_key.this[0].tags), "fintechbankx.io/secrets")
    error_message = "The storage key must not carry fintechbankx.io/secrets (External Secrets may not decrypt storage)."
  }

  assert {
    condition     = aws_kms_key.secrets[0].tags["fintechbankx.io/secrets"] == "true" && aws_kms_key.secrets[0].enable_key_rotation
    error_message = "The secrets key is tagged fintechbankx.io/secrets=true and rotates."
  }

  assert {
    condition     = aws_kms_alias.this[0].name == "alias/dev-payment-request-to-pay-service-db-storage" && aws_kms_alias.secrets[0].name == "alias/dev-payment-request-to-pay-service-db-secrets"
    error_message = "Aliases <name>-db-storage and <name>-db-secrets."
  }

  assert {
    condition = (
      aws_rds_cluster.this.kms_key_id == aws_kms_key.this[0].arn &&
      alltrue([for i in aws_rds_cluster_instance.this : i.performance_insights_kms_key_id == aws_kms_key.this[0].arn])
    )
    error_message = "Storage, snapshots and Performance Insights use the storage key."
  }

  assert {
    condition = (
      aws_rds_cluster.this.master_user_secret_kms_key_id == aws_kms_key.secrets[0].arn &&
      alltrue([for s in concat(aws_secretsmanager_secret.app, aws_secretsmanager_secret.migration) : s.kms_key_id == aws_kms_key.secrets[0].arn])
    )
    error_message = "Every Secrets Manager secret (master, db-app, db-migration) uses the secrets key."
  }

  assert {
    condition     = output.kms_key_arn == aws_kms_key.this[0].arn && output.secrets_kms_key_arn == aws_kms_key.secrets[0].arn
    error_message = "kms_key_arn outputs the storage key, secrets_kms_key_arn the secrets key."
  }
}

run "caller_keys_override_each_role" {
  command = apply

  variables {
    kms_key_arn         = "arn:aws:kms:me-central-1:111122223333:key/11111111-1111-4111-8111-111111111111"
    secrets_kms_key_arn = "arn:aws:kms:me-central-1:111122223333:key/22222222-2222-4222-8222-222222222222"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && length(aws_kms_key.secrets) == 0
    error_message = "Caller-provided keys replace the module keys."
  }

  assert {
    condition = (
      aws_rds_cluster.this.kms_key_id == var.kms_key_arn &&
      aws_rds_cluster.this.master_user_secret_kms_key_id == var.secrets_kms_key_arn &&
      aws_secretsmanager_secret.app[0].kms_key_id == var.secrets_kms_key_arn &&
      aws_secretsmanager_secret.migration[0].kms_key_id == var.secrets_kms_key_arn
    )
    error_message = "kms_key_arn overrides storage only; secrets_kms_key_arn overrides the secrets key."
  }
}

run "one_key_for_both_rejected" {
  command = plan

  variables {
    kms_key_arn         = "arn:aws:kms:me-central-1:111122223333:key/11111111-1111-4111-8111-111111111111"
    secrets_kms_key_arn = "arn:aws:kms:me-central-1:111122223333:key/11111111-1111-4111-8111-111111111111"
  }

  expect_failures = [aws_rds_cluster.this]
}
