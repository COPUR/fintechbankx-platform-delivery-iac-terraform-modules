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
    condition     = strcontains(output.role_bootstrap_sql, "CREATE EXTENSION IF NOT EXISTS pgaudit;")
    error_message = "The bootstrap registers pgaudit when it is enabled."
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

# PostgreSQL 16 (Aurora 16): the RDS admin is CREATEROLE, not superuser. A
# role it creates is granted back to it with ADMIN only (no SET, no INHERIT),
# so CREATE SCHEMA ... AUTHORIZATION <owner> and default privileges for the
# owner fail unless the admin first takes SET on the owner, acts as the owner
# and gives the membership back (proved on a local PostgreSQL 16, README
# "Aurora 16 drill").
run "pg16_createrole_admin_acts_as_owner_then_drops_membership" {
  command = apply

  assert {
    condition     = length(regexall("(?s)GRANT payment_request_to_pay_migration TO CURRENT_USER WITH SET TRUE, INHERIT FALSE;.*CREATE SCHEMA IF NOT EXISTS sc_pay_request_to_pay AUTHORIZATION payment_request_to_pay_migration;.*SET ROLE payment_request_to_pay_migration;.*GRANT USAGE ON SCHEMA sc_pay_request_to_pay TO payment_request_to_pay_app;.*ALTER DEFAULT PRIVILEGES FOR ROLE payment_request_to_pay_migration IN SCHEMA sc_pay_request_to_pay GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO payment_request_to_pay_app;.*ALTER DEFAULT PRIVILEGES FOR ROLE payment_request_to_pay_migration IN SCHEMA sc_pay_request_to_pay GRANT USAGE, SELECT ON SEQUENCES TO payment_request_to_pay_app;.*RESET ROLE;.*REVOKE payment_request_to_pay_migration FROM CURRENT_USER;", output.role_bootstrap_sql)) == 1
    error_message = "Order: GRANT owner TO CURRENT_USER WITH SET TRUE, INHERIT FALSE; CREATE SCHEMA AUTHORIZATION owner; SET ROLE owner; GRANT USAGE; ALTER DEFAULT PRIVILEGES x2; RESET ROLE; REVOKE owner FROM CURRENT_USER."
  }

  assert {
    condition     = length(regexall("(?s)REVOKE payment_request_to_pay_migration FROM CURRENT_USER;.*SET ROLE", output.role_bootstrap_sql)) == 0
    error_message = "The admin keeps no SET membership on the owner after the bootstrap."
  }
}

# pgaudit object auditing: pgaudit.role = rds_pgaudit, and the bootstrap
# creates that role idempotently (it may already exist on the cluster).
run "pgaudit_object_audit_role_created_idempotently" {
  command = apply

  assert {
    condition     = strcontains(output.role_bootstrap_sql, "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_pgaudit') THEN CREATE ROLE rds_pgaudit NOLOGIN; END IF; END $$;")
    error_message = "The bootstrap creates the pgaudit object-audit role rds_pgaudit if it does not exist."
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "pgaudit.role"]) == "rds_pgaudit"
    error_message = "pgaudit.role must be rds_pgaudit."
  }
}
