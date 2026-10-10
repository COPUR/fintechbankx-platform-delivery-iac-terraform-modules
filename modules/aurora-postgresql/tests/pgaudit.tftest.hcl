# Offline (mock provider): pgaudit is preloaded and logs DDL and role changes
# by default (schema changes and grants are audit evidence); it can be turned
# off per caller.

mock_provider "aws" {}

variables {
  name                       = "dev-payment-request-to-pay-service"
  database_name              = "db_pay_request_to_pay_dev"
  master_username            = "rtp_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/payment-request-to-pay-service/db-app"
}

run "pgaudit_on_by_default" {
  command = plan

  assert {
    condition     = contains(split(",", one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "shared_preload_libraries"])), "pgaudit")
    error_message = "shared_preload_libraries must include pgaudit."
  }

  # Setting the parameter replaces the Aurora default (pg_stat_statements), so
  # the module must keep it next to pgaudit: query statistics stay available.
  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "shared_preload_libraries"]) == "pg_stat_statements,pgaudit"
    error_message = "shared_preload_libraries must be pg_stat_statements,pgaudit (keep the Aurora default pg_stat_statements)."
  }

  assert {
    condition     = contains(split(",", one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "shared_preload_libraries"])), "pg_stat_statements")
    error_message = "shared_preload_libraries must include pg_stat_statements."
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.apply_method if p.name == "shared_preload_libraries"]) == "pending-reboot"
    error_message = "shared_preload_libraries is static: apply_method pending-reboot."
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "pgaudit.log"]) == "ddl,role"
    error_message = "pgaudit.log must default to ddl,role."
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "pgaudit.role"]) == "rds_pgaudit"
    error_message = "pgaudit.role must be rds_pgaudit (object audit of the audit tables)."
  }

  assert {
    condition     = local.roles_named == false
    error_message = "Without role names no bootstrap SQL is rendered."
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "rds.force_ssl stays 1."
  }
}

run "pgaudit_classes_configurable" {
  command = plan

  variables {
    pgaudit_log_classes = ["ddl", "role", "write"]
  }

  assert {
    condition     = one([for p in aws_rds_cluster_parameter_group.this.parameter : p.value if p.name == "pgaudit.log"]) == "ddl,role,write"
    error_message = "pgaudit.log follows pgaudit_log_classes."
  }
}

run "pgaudit_can_be_disabled" {
  command = plan

  variables {
    pgaudit_enabled = false
  }

  assert {
    condition     = length([for p in aws_rds_cluster_parameter_group.this.parameter : p if p.name == "shared_preload_libraries" || startswith(p.name, "pgaudit.")]) == 0
    error_message = "With pgaudit_enabled = false no pgaudit parameter is set."
  }
}

run "unknown_pgaudit_class_rejected" {
  command = plan

  variables {
    pgaudit_log_classes = ["ddl", "everything"]
  }

  expect_failures = [var.pgaudit_log_classes]
}
