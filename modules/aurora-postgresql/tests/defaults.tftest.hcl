# Offline (mock provider): TLS enforced, encryption at rest, safe defaults.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "me-central-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}


variables {
  name                       = "dev-loan-lifecycle-service"
  database_name              = "loan_lifecycle"
  master_username            = "loan_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "rds.force_ssl must be 1."
  }

  assert {
    condition     = aws_rds_cluster.this.storage_encrypted == true
    error_message = "Storage must be encrypted."
  }

  assert {
    condition     = aws_rds_cluster.this.deletion_protection == true
    error_message = "Deletion protection must default to true."
  }

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating CMK must be created when none is passed."
  }

  assert {
    condition     = aws_rds_cluster.this.tags["fintechbankx.io/observability"] == "enabled"
    error_message = "Clusters must be discoverable by YACE."
  }
}

run "reserved_master_username_rejected" {
  command = plan

  variables {
    master_username = "postgres"
  }

  expect_failures = [var.master_username]
}

run "two_role_secrets" {
  command = plan

  variables {
    app_secret_name       = "dev/compliance-evidence-service/db-app"
    migration_secret_name = "dev/compliance-evidence-service/db-migration"
  }

  assert {
    condition     = aws_secretsmanager_secret.app[0].name == "dev/compliance-evidence-service/db-app"
    error_message = "Runtime role secret must be <env>/<service-slug>/db-app."
  }

  assert {
    condition     = aws_secretsmanager_secret.migration[0].name == "dev/compliance-evidence-service/db-migration"
    error_message = "Owner (migration) role secret must be <env>/<service-slug>/db-migration."
  }
}

run "migration_secret_name_convention" {
  command = plan

  variables {
    migration_secret_name = "dev/compliance-evidence-service/db-app"
  }

  expect_failures = [var.migration_secret_name]
}
