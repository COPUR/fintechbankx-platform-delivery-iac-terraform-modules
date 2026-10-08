# Offline (mock provider): the DBA bootstrap SQL of the two-role pattern for
# request-to-pay (PR #14 review): the owner role owns the schema and runs
# Flyway; the runtime role gets USAGE and DML only, never DDL or TRUNCATE.

mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-000000000001"
    }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:me-central-1:111122223333:secret:rds-admin-AbCdEf"
        kms_key_id    = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-000000000001"
        secret_status = "active"
      }]
    }
  }
}

variables {
  name                       = "dev-payment-request-to-pay-service"
  database_name              = "db_pay_request_to_pay_dev"
  master_username            = "rtp_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/payment-request-to-pay-service/db-app"
  schema_name                = "sc_pay_request_to_pay"
  app_role_name              = "payment_request_to_pay_app"
  migration_role_name        = "payment_request_to_pay_migration"
}

run "owner_owns_the_schema_runtime_gets_dml_only" {
  command = apply

  assert {
    condition     = strcontains(output.role_bootstrap_sql, "CREATE SCHEMA IF NOT EXISTS sc_pay_request_to_pay AUTHORIZATION payment_request_to_pay_migration;")
    error_message = "The migration (owner) role must own the schema."
  }

  assert {
    condition     = strcontains(output.role_bootstrap_sql, "GRANT USAGE ON SCHEMA sc_pay_request_to_pay TO payment_request_to_pay_app;")
    error_message = "The runtime role needs USAGE on the schema."
  }

  assert {
    condition     = strcontains(output.role_bootstrap_sql, "ALTER DEFAULT PRIVILEGES FOR ROLE payment_request_to_pay_migration IN SCHEMA sc_pay_request_to_pay GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO payment_request_to_pay_app;")
    error_message = "Tables created by Flyway must grant DML (and only DML) to the runtime role."
  }

  assert {
    condition     = length(regexall("(?i)GRANT[^;]*(CREATE|TRUNCATE|ALL|REFERENCES|TRIGGER)[^;]*TO payment_request_to_pay_app", output.role_bootstrap_sql)) == 0
    error_message = "The runtime role must never get DDL, TRUNCATE, REFERENCES, TRIGGER or ALL."
  }

  assert {
    condition     = length(regexall("(?i)PASSWORD\\s+'", output.role_bootstrap_sql)) == 0
    error_message = "The SQL must not carry a password literal; the DBA sets it from the secret."
  }

  assert {
    condition     = strcontains(output.role_bootstrap_sql, "REVOKE CREATE ON SCHEMA public FROM PUBLIC;")
    error_message = "Nobody may create objects in the public schema."
  }
}

run "no_sql_without_role_names" {
  command = apply

  variables {
    schema_name         = null
    app_role_name       = null
    migration_role_name = null
  }

  assert {
    condition     = output.role_bootstrap_sql == null
    error_message = "Without schema and role names the module renders no bootstrap SQL."
  }
}

run "runtime_and_owner_roles_must_differ" {
  command = plan

  variables {
    migration_role_name = "payment_request_to_pay_app"
  }

  expect_failures = [var.migration_role_name]
}
