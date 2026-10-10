# Offline (mock providers): ADR-023 KMS split. The storage key (cluster
# storage and snapshots) is not tagged fintechbankx.io/secrets, so the
# External Secrets roles can never decrypt with it; both Secrets Manager
# secrets (docdb-master, docdb-app) use the separate, tagged secrets key.

mock_provider "aws" {}
mock_provider "random" {}

override_resource {
  target = aws_kms_key.this
  values = { arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-0000000000a1" }
}

override_resource {
  target = aws_kms_key.secrets
  values = { arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-0000000000b2" }
}

variables {
  environment                = "dev"
  service_slug               = "personal-financial-data-service"
  name                       = "dev-of-personal-financial-data"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
}

run "storage_and_secrets_keys_are_separate" {
  command = apply

  assert {
    condition     = length(aws_kms_key.this) == 1 && !contains(keys(aws_kms_key.this[0].tags), "fintechbankx.io/secrets")
    error_message = "The storage key must not carry fintechbankx.io/secrets."
  }

  assert {
    condition     = aws_kms_key.secrets[0].tags["fintechbankx.io/secrets"] == "true" && aws_kms_key.secrets[0].enable_key_rotation
    error_message = "The secrets key is tagged fintechbankx.io/secrets=true and rotates."
  }

  assert {
    condition     = aws_kms_alias.this[0].name == "alias/dev-of-personal-financial-data-docdb-storage" && aws_kms_alias.secrets[0].name == "alias/dev-of-personal-financial-data-docdb-secrets"
    error_message = "Aliases <name>-docdb-storage and <name>-docdb-secrets."
  }

  assert {
    condition     = aws_docdb_cluster.this.kms_key_id == aws_kms_key.this[0].arn
    error_message = "Cluster storage and snapshots use the storage key."
  }

  assert {
    condition     = alltrue([for s in [aws_secretsmanager_secret.master, aws_secretsmanager_secret.app] : s.kms_key_id == aws_kms_key.secrets[0].arn])
    error_message = "Every Secrets Manager secret (docdb-master, docdb-app) uses the secrets key."
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
    condition = (
      length(aws_kms_key.this) == 0 && length(aws_kms_key.secrets) == 0 &&
      aws_docdb_cluster.this.kms_key_id == var.kms_key_arn &&
      aws_secretsmanager_secret.master.kms_key_id == var.secrets_kms_key_arn &&
      aws_secretsmanager_secret.app.kms_key_id == var.secrets_kms_key_arn
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

  expect_failures = [aws_docdb_cluster.this]
}
