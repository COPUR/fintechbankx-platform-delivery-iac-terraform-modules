# Offline (mock provider): the operator-filled credential secrets (db-app,
# db-migration) are never tagged fintechbankx.io/value-in-state=true, even
# when the caller passes that tag in var.tags; the tf-plan role may read only
# secret values carrying that tag, so a caller cannot make them PR-readable.

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
  app_secret_name            = "dev/loan-lifecycle-service/db-app"
}

run "credential_secrets_are_not_value_in_state_by_default" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.app[0].tags["fintechbankx.io/value-in-state"] == "false" && aws_secretsmanager_secret.migration[0].tags["fintechbankx.io/value-in-state"] == "false"
    error_message = "db-app and db-migration must be tagged fintechbankx.io/value-in-state=false."
  }
}

run "caller_tags_cannot_mark_credentials_value_in_state" {
  command = plan

  variables {
    tags = { "fintechbankx.io/value-in-state" = "true", Team = "lending" }
  }

  assert {
    condition     = aws_secretsmanager_secret.app[0].tags["fintechbankx.io/value-in-state"] == "false" && aws_secretsmanager_secret.migration[0].tags["fintechbankx.io/value-in-state"] == "false"
    error_message = "var.tags must not make db-app or db-migration readable by the tf-plan role."
  }

  assert {
    condition     = aws_secretsmanager_secret.app[0].tags["Team"] == "lending" && aws_rds_cluster.this.tags["fintechbankx.io/value-in-state"] == "true"
    error_message = "Other caller tags still apply (only the credential secrets pin value-in-state)."
  }
}
