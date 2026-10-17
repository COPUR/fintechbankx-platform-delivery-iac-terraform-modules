# Offline (mock providers): ADR-023 KMS split. The storage key (at-rest
# encryption and snapshots) is not tagged fintechbankx.io/secrets, so the
# External Secrets roles can never decrypt with it; the connection secret
# <env>/<slug>/redis uses the separate, tagged secrets key.

mock_provider "aws" {}
mock_provider "random" {}

# A token the ElastiCache schema accepts (the mock random string may not).
override_resource {
  target = random_password.auth
  values = { result = "MockAuthTokenOnlyForOfflineTests0123456789abcdefghijklmnopqrstuv" }
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
  environment                = "dev"
  service_slug               = "banking-metadata-service"
  name                       = "dev-of-banking-metadata"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
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
    condition     = aws_kms_alias.this[0].name == "alias/dev-of-banking-metadata-redis-storage" && aws_kms_alias.secrets[0].name == "alias/dev-of-banking-metadata-redis-secrets"
    error_message = "Aliases <name>-redis-storage and <name>-redis-secrets."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == aws_kms_key.this[0].arn
    error_message = "At-rest encryption and snapshots use the storage key."
  }

  assert {
    condition     = aws_secretsmanager_secret.redis.kms_key_id == aws_kms_key.secrets[0].arn
    error_message = "The connection secret uses the secrets key."
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
      aws_elasticache_replication_group.this.kms_key_id == var.kms_key_arn &&
      aws_secretsmanager_secret.redis.kms_key_id == var.secrets_kms_key_arn
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

  expect_failures = [aws_elasticache_replication_group.this]
}
