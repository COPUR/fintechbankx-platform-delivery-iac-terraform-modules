# Offline (mock provider): personal operator logins for one service database
# through IAM database authentication. Each listed Identity Center user may
# connect only as their own database login, and the login SQL keeps those
# logins and their group apart from the service's own database users.

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
}

variables {
  environment         = "dev"
  service_slug        = "accounts-ledger-service"
  database_name       = "db_acc_accounts_ledger_dev"
  cluster_resource_id = "cluster-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  operator_group_role = "accounts_ledger_operator"
  operators = {
    "jane.doe@bank.example" = "op_jane_doe"
    "omar.k@bank.example"   = "op_omar_k"
  }
  reserved_db_users = ["accounts_admin", "accounts_app", "accounts_migration"]
}

run "one_connect_statement_per_operator" {
  command = plan

  assert {
    condition     = aws_iam_policy.connect.name == "dev-accounts-ledger-service-db-operator-login"
    error_message = "Policy name <env>-<slug>-db-operator-login (the permission set references it by name)."
  }

  assert {
    condition = toset([for s in jsondecode(aws_iam_policy.connect.policy).Statement : "${s.Effect}|${s.Action}|${s.Resource}|${s.Condition.StringLike["aws:userid"]}"]) == toset([
      "Allow|rds-db:connect|arn:aws:rds-db:me-central-1:111122223333:dbuser:cluster-ABCDEFGHIJKLMNOPQRSTUVWXYZ/op_jane_doe|*:jane.doe@bank.example",
      "Allow|rds-db:connect|arn:aws:rds-db:me-central-1:111122223333:dbuser:cluster-ABCDEFGHIJKLMNOPQRSTUVWXYZ/op_omar_k|*:omar.k@bank.example",
    ])
    error_message = "Each operator may connect only as their own login, and only from a session named after them."
  }

  assert {
    condition     = length(jsondecode(aws_iam_policy.connect.policy).Statement) == 2
    error_message = "Nothing but the per-operator connect statements."
  }
}

run "login_sql_desired_state" {
  command = plan

  assert {
    condition     = strcontains(output.login_sql, "grp        constant text   := 'accounts_ledger_operator';")
    error_message = "The SQL manages the operator group."
  }

  assert {
    condition     = strcontains(output.login_sql, "ops        constant text[] := ARRAY['op_jane_doe', 'op_omar_k'];")
    error_message = "The SQL lists every operator login, sorted."
  }

  assert {
    condition     = strcontains(output.login_sql, "reserved   constant text[] := ARRAY['accounts_admin', 'accounts_app', 'accounts_migration'];")
    error_message = "The SQL knows the service's own users, which must never join the group."
  }

  assert {
    condition     = strcontains(output.login_sql, "db         constant text   := 'db_acc_accounts_ledger_dev';")
    error_message = "The SQL refuses to run in another database."
  }

  assert {
    condition     = strcontains(output.login_sql, "only its grantor can revoke it") && strcontains(output.login_sql, "rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls")
    error_message = "The SQL stops on a membership it cannot revoke and checks role attributes."
  }

  assert {
    condition     = !strcontains(output.login_sql, "NOSUPERUSER") && !strcontains(output.login_sql, "NOBYPASSRLS")
    error_message = "The master user (rds_superuser, not a superuser) may not set SUPERUSER or BYPASSRLS: check them, never set them."
  }

  assert {
    condition     = jsonencode(output.operator_logins) == jsonencode({ "jane.doe@bank.example" = "op_jane_doe", "omar.k@bank.example" = "op_omar_k" })
    error_message = "operator_logins echoes the map."
  }
}

run "login_needs_op_prefix" {
  command = plan

  variables {
    operators = { "jane.doe@bank.example" = "accounts_app" }
  }

  expect_failures = [var.operators]
}

run "one_login_per_person" {
  command = plan

  variables {
    operators = {
      "jane.doe@bank.example" = "op_shared"
      "omar.k@bank.example"   = "op_shared"
    }
  }

  expect_failures = [var.operators]
}

run "wildcard_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "*" = "op_anyone" }
  }

  expect_failures = [var.operators]
}

run "question_mark_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "jane.do?@bank.example" = "op_jane_doe" }
  }

  expect_failures = [var.operators]
}

run "no_operators_rejected" {
  command = plan

  variables {
    operators = {}
  }

  expect_failures = [var.operators]
}

run "group_must_not_be_a_system_or_operator_name" {
  command = plan

  variables {
    operator_group_role = "rds_superuser"
  }

  expect_failures = [var.operator_group_role]
}

run "group_must_not_be_a_service_user" {
  command = plan

  variables {
    operator_group_role = "accounts_app"
  }

  expect_failures = [aws_iam_policy.connect]
}

run "reserved_users_required" {
  command = plan

  variables {
    reserved_db_users = []
  }

  expect_failures = [var.reserved_db_users]
}

run "cluster_resource_id_not_identifier" {
  command = plan

  variables {
    cluster_resource_id = "dev-accounts-ledger-service-aurora"
  }

  expect_failures = [var.cluster_resource_id]
}
