# Offline (mock provider): personal operator logins for one service database
# through IAM database authentication. Each listed Identity Center user may
# connect only from a session named after them, and the login SQL keeps
# those logins and their group apart from the service's own database users.

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
    condition     = strcontains(output.login_sql, "users      constant text[] := ARRAY['jane.doe@bank.example', 'omar.k@bank.example'];")
    error_message = "The SQL gets each login's Identity Center user name, in the order of the logins."
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
    condition     = strcontains(output.login_sql, "rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls")
    error_message = "The SQL checks role attributes."
  }

  assert {
    condition     = !strcontains(output.login_sql, "NOSUPERUSER") && !strcontains(output.login_sql, "NOBYPASSRLS")
    error_message = "The master user (rds_superuser, not a superuser) may not set SUPERUSER or BYPASSRLS: check them, never set them."
  }

  assert {
    condition     = strcontains(output.login_sql, "idle_tx    constant text   := '60s';")
    error_message = "Each login gets idle_in_transaction_session_timeout (default 60 s), so an idle operator transaction cannot hold the relay's rows."
  }

  assert {
    condition     = jsonencode(output.operator_logins) == jsonencode({ "jane.doe@bank.example" = "op_jane_doe", "omar.k@bank.example" = "op_omar_k" })
    error_message = "operator_logins echoes the map."
  }

  assert {
    condition     = strcontains(output.login_sql, "ro         constant boolean := false;") && strcontains(output.login_sql, "EXECUTE format('ALTER ROLE %I RESET default_transaction_read_only', op);")
    error_message = "Without read_only the logins keep no read-only default (a switch back resets it)."
  }

  # One transaction, carried by the file itself: the DBA runs it without --single-transaction.
  assert {
    condition     = length(regexall("(?m)^BEGIN;$", output.login_sql)) == 1 && length(regexall("(?m)^COMMIT;$", output.login_sql)) == 1
    error_message = "Operator mode is one transaction: one BEGIN and one COMMIT in the file."
  }

  assert {
    condition     = strcontains(output.login_sql, "-v ON_ERROR_STOP=1 -f login.sql") && !strcontains(output.login_sql, "--single-transaction")
    error_message = "The header's psql line keeps ON_ERROR_STOP and drops --single-transaction (the file has its own BEGIN and COMMIT)."
  }

  # PostgreSQL 16's createrole_self_grant would give the master SET and INHERIT on every role
  # it creates; the run switches it off before it creates any.
  assert {
    condition     = strcontains(output.login_sql, "BEGIN;\nSET LOCAL lock_timeout = '5s';\nSET LOCAL createrole_self_grant = '';\n") && length(regexall("SET LOCAL createrole_self_grant", output.login_sql)) == 1
    error_message = "The transaction that creates roles starts with SET LOCAL createrole_self_grant = ''."
  }

  # rds_iam without SET: a login cannot act as rds_iam (and so cannot make objects rds_iam owns).
  assert {
    condition     = strcontains(output.login_sql, "        EXECUTE format('GRANT rds_iam TO %I WITH INHERIT TRUE, SET FALSE', op);\n") && length(regexall("GRANT rds_iam TO", output.login_sql)) == 1
    error_message = "Each login gets rds_iam WITH INHERIT TRUE, SET FALSE, and nowhere a plain GRANT rds_iam."
  }

  assert {
    condition = alltrue([for check in [
      "WHERE m.roleid = 'rds_iam'::regrole AND m.member = op::regrole::oid AND (m.admin_option OR m.set_option)",
      "WHERE r.rolname <> op AND (pg_has_role(op, r.oid, 'SET') OR pg_has_role(op, r.oid, 'MEMBER WITH ADMIN OPTION'))",
    ] : strcontains(output.login_sql, check)])
    error_message = "The SQL stops when a login's rds_iam membership has SET or ADMIN, and when a login can SET ROLE to, or grant, any other role."
  }

  # Retirement revokes an rds_iam grant the master made itself or through a role it has the
  # privileges of (rds_superuser, when that role holds ADMIN on rds_iam).
  assert {
    condition     = strcontains(output.login_sql, "WHERE g.rolname = 'rds_iam' AND m.member = op::regrole::oid AND pg_has_role(master, m.grantor, 'USAGE')) THEN")
    error_message = "Retirement revokes rds_iam when the master made the grant itself or through a role it has the privileges of."
  }

  assert {
    condition     = strcontains(output.login_sql, "undone     constant text   := 'This transaction was rolled back, so nothing was changed';")
    error_message = "In operator mode a stop rolls back the one transaction, and the message says nothing was changed."
  }
}

# Module ownership marks (COMMENT ON ROLE): the SQL adopts only roles it made, for the same person.
run "login_sql_ownership_marks" {
  command = plan

  assert {
    condition     = strcontains(output.login_sql, "grp_mark   constant text   := 'operator-db-login group dev/accounts-ledger-service';")
    error_message = "The group's mark names the module instance (environment and service)."
  }

  assert {
    condition     = strcontains(output.login_sql, "prefix     constant text   := 'operator-db-login accounts_ledger_operator: ';")
    error_message = "Each login's mark names the group, then the person's Identity Center user name."
  }

  assert {
    condition = alltrue([for line in [
      "EXECUTE format('COMMENT ON ROLE %I IS %L', grp, grp_mark);",
      "EXECUTE format('COMMENT ON ROLE %I IS %L', op, prefix || usr);",
      "EXECUTE format('COMMENT ON ROLE %I IS %L', op, mark || ' (retired)');",
    ] : strcontains(output.login_sql, line)])
    error_message = "The SQL marks the group and each login when it creates them, and marks a login retired."
  }

  assert {
    condition = alltrue([for message in [
      "exists but this module did not create it",
      "was retired; a retired login is never enabled again",
      "was made for someone else",
      "belongs to another group",
      "has members this module did not add",
      "was changed outside this SQL",
    ] : strcontains(output.login_sql, message)])
    error_message = "The SQL stops on an unmarked group or login, a retired or reassigned login, a foreign group member and a tampered login."
  }

  # Tampering it stops on instead of repairing (evidence stays in the catalog).
  assert {
    condition = alltrue([for check in [
      "s.setdatabase <> 0",
      "<> ALL (managed)",
      "FROM pg_shdepend s",
      "m.grantor = 10",
      "NOT pg_has_role(r.oid, 'rds_iam', 'MEMBER')",
    ] : strcontains(output.login_sql, check)])
    error_message = "The SQL checks per-database and unmanaged settings, owned objects and privileges in every database, foreign memberships and rds_iam."
  }

  # Retirement covers every marked login of the group, member or not.
  assert {
    condition     = strcontains(output.login_sql, "starts_with(coalesce(shobj_description(r.oid, 'pg_authid'), ''), prefix)") && strcontains(output.login_sql, "AND r.rolname <> ALL (ops)")
    error_message = "Every login marked for this group that is no longer listed is retired, whether or not it is still in the group."
  }
}

# pgaudit: every statement class a person runs is logged under their login; no pgaudit, no logins.
run "login_sql_pgaudit" {
  command = plan

  assert {
    condition     = strcontains(output.login_sql, "audit_log  constant text   := 'read,write,ddl,role';") && strcontains(output.login_sql, "        EXECUTE format('ALTER ROLE %I SET pgaudit.log = %L', op, audit_log);\n")
    error_message = "Each login gets pgaudit.log = read,write,ddl,role."
  }

  assert {
    condition     = strcontains(output.login_sql, "IF NOT EXISTS (SELECT 1 FROM pg_settings WHERE name = 'pgaudit.log') THEN") && strcontains(output.login_sql, "add pgaudit to shared_preload_libraries in the cluster parameter group")
    error_message = "Without pgaudit loaded the SQL stops and names the parameter group change."
  }
}

# The exact idle-transaction statement, inside the per-login loop.
run "idle_in_transaction_timeout_per_login" {
  command = plan

  assert {
    condition = anytrue([
      for block in slice(split("FOREACH op IN ARRAY ops LOOP\n", output.login_sql), 1, length(split("FOREACH op IN ARRAY ops LOOP\n", output.login_sql))) :
      strcontains(split("END LOOP;", block)[0], "        EXECUTE format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L', op, idle_tx);\n")
    ])
    error_message = "EXECUTE format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L', op, idle_tx); runs inside FOREACH op IN ARRAY ops LOOP."
  }

  assert {
    condition     = length(split("SET idle_in_transaction_session_timeout", output.login_sql)) == 2
    error_message = "The idle-transaction setting is set in one place only."
  }
}

run "idle_in_transaction_timeout_lowest" {
  command = plan

  variables {
    idle_in_transaction_timeout_seconds = 5
  }

  assert {
    condition     = strcontains(output.login_sql, "idle_tx    constant text   := '5s';")
    error_message = "5 seconds is allowed."
  }
}

run "idle_in_transaction_timeout_highest" {
  command = plan

  variables {
    idle_in_transaction_timeout_seconds = 600
  }

  assert {
    condition     = strcontains(output.login_sql, "idle_tx    constant text   := '600s';")
    error_message = "600 seconds is allowed."
  }
}

run "idle_in_transaction_timeout_below_range" {
  command = plan

  variables {
    idle_in_transaction_timeout_seconds = 4
  }

  expect_failures = [var.idle_in_transaction_timeout_seconds]
}

run "idle_in_transaction_timeout_above_range" {
  command = plan

  variables {
    idle_in_transaction_timeout_seconds = 601
  }

  expect_failures = [var.idle_in_transaction_timeout_seconds]
}

run "idle_in_transaction_timeout_whole_seconds" {
  command = plan

  variables {
    idle_in_transaction_timeout_seconds = 1.5
  }

  expect_failures = [var.idle_in_transaction_timeout_seconds]
}

run "read_only_logins" {
  command = plan

  variables {
    service_slug        = "loan-lifecycle-service"
    database_name       = "db_ln_loan_lifecycle_dev"
    operator_group_role = "loan_lifecycle_readonly"
    reserved_db_users   = ["loan_admin", "loan_lifecycle_app", "loan_lifecycle_owner"]
    read_only           = true
  }

  assert {
    condition     = aws_iam_policy.connect.name == "dev-loan-lifecycle-service-db-readonly-login"
    error_message = "A read-only module instance has its own policy name, so it can sit next to an operator one."
  }

  assert {
    condition     = strcontains(output.login_sql, "ro         constant boolean := true;") && strcontains(output.login_sql, "EXECUTE format('ALTER ROLE %I SET default_transaction_read_only = on', op);")
    error_message = "Read-only logins default every transaction to read only."
  }

  # Two transactions: the first takes LOGIN away from every login of the group and commits, the
  # second gives it back only after the check passed.
  assert {
    condition     = length(regexall("(?m)^BEGIN;$", output.login_sql)) == 2 && length(regexall("(?m)^COMMIT;$", output.login_sql)) == 2
    error_message = "Read-only mode is two transactions."
  }

  assert {
    condition     = strcontains(split("\nCOMMIT;\n", output.login_sql)[0], "EXECUTE format('ALTER ROLE %I NOLOGIN', op);") && !strcontains(split("\nCOMMIT;\n", output.login_sql)[0], "ALTER ROLE %I LOGIN")
    error_message = "The first transaction takes LOGIN away from the group's logins."
  }

  # The desired-state statement leaves read-only logins without LOGIN; only the passing check gives it back.
  assert {
    condition     = strcontains(output.login_sql, "        EXECUTE format('ALTER ROLE %I %s INHERIT CONNECTION LIMIT %s PASSWORD NULL', op, CASE WHEN ro THEN 'NOLOGIN' ELSE 'LOGIN' END, conn_limit);\n") && length(regexall("ALTER ROLE %I LOGIN", output.login_sql)) == 1
    error_message = "In read-only mode the per-login ALTER ROLE keeps NOLOGIN, and ALTER ROLE ... LOGIN appears once, after the check."
  }

  assert {
    condition     = can(regex("(?s)RAISE EXCEPTION 'read-only logins of %.*FOREACH op IN ARRAY ops LOOP\n\\s*EXECUTE format\\('ALTER ROLE %I LOGIN', op\\);", output.login_sql))
    error_message = "LOGIN comes back only after the check, in the second transaction."
  }

  # The group mark names the mode, and the first transaction checks it before it takes LOGIN
  # away, so a read-only instance given an operator group's name stops without touching it.
  assert {
    condition     = strcontains(output.login_sql, "grp_mark   constant text   := 'operator-db-login group dev/loan-lifecycle-service read-only';") && strcontains(split("\nCOMMIT;\n", output.login_sql)[0], "    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = grp)\n       AND shobj_description(grp::regrole::oid, 'pg_authid') IS DISTINCT FROM grp_mark THEN\n        RAISE EXCEPTION")
    error_message = "A read-only group's mark ends in ' read-only', and transaction 1 stops on a group without that mark."
  }

  assert {
    condition     = strcontains(split("\nCOMMIT;\n", output.login_sql)[1], "SET LOCAL createrole_self_grant = '';") && !strcontains(split("\nCOMMIT;\n", output.login_sql)[0], "SET LOCAL createrole_self_grant")
    error_message = "createrole_self_grant is switched off in the transaction that creates roles."
  }

  # A stop rolls back the second transaction only: the messages must not say nothing changed.
  assert {
    condition     = !strcontains(lower(output.login_sql), "nothing was changed") && strcontains(output.login_sql, "undone     constant text   := 'This transaction was rolled back; the read-only logins stay without LOGIN (the first transaction took it away) until a run passes';")
    error_message = "In read-only mode the stop messages say the logins stay without LOGIN, never that nothing was changed."
  }

  assert {
    condition     = strcontains(output.login_sql, "Sessions already open are not ended: end them with pg_terminate_backend")
    error_message = "A failed read-only check tells the DBA that open sessions keep running."
  }

  # Large objects a login may write: owned by, or UPDATE granted to, any role it has the
  # privileges of (rds_iam included), or PUBLIC; or every one when lo_compat_privileges is on.
  assert {
    condition = alltrue([for check in [
      "WHERE pg_has_role(w.who, l.lomowner, 'USAGE')",
      "AND (a.grantee = 0 OR pg_has_role(w.who, a.grantee, 'USAGE'))",
      "WHERE current_setting('lo_compat_privileges')::boolean",
    ] : strcontains(output.login_sql, check)])
    error_message = "The read-only check reports large objects a login may write through any role it has the privileges of, and lo_compat_privileges."
  }

  # pgaudit's own event-trigger functions are SECURITY DEFINER and executable by PUBLIC; only
  # a superuser can attach an event trigger, so functions returning event_trigger are exempt.
  assert {
    condition     = strcontains(output.login_sql, "AND p.prosecdef AND p.prorettype <> 'event_trigger'::regtype")
    error_message = "SECURITY DEFINER functions returning event_trigger (pgaudit's) do not stop the read-only check; every other one does."
  }

  # Effective privileges of every login (its own grants, the group's, rds_iam's and PUBLIC's).
  assert {
    condition = alltrue([for check in [
      "has_database_privilege(w.who, db, 'CREATE')",
      "has_schema_privilege(w.who, n.oid, 'CREATE')",
      "has_table_privilege(w.who, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')",
      "has_any_column_privilege(w.who, c.oid, 'INSERT,UPDATE,REFERENCES')",
      "has_sequence_privilege(w.who, c.oid, 'USAGE,UPDATE')",
      "has_function_privilege(w.who, p.oid, 'EXECUTE')",
      "FROM pg_default_acl d",
      "FROM unnest(ops) AS w(who), pg_largeobject_metadata l",
      "e.extowner",
      "can change data in",
    ] : strcontains(output.login_sql, check)])
    error_message = "In read-only mode the SQL stops when a login can write anything in the database (directly, through the group, rds_iam or PUBLIC), through default privileges or large objects, or can run a SECURITY DEFINER function a service role could have planted."
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

# User names of valid length that carry IAM wildcards or policy-variable syntax: a name like "**"
# would make the condition "*:**" and match any session.
run "wildcard_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "*@bank.example" = "op_anyone" }
  }

  expect_failures = [var.operators]
}

run "only_wildcards_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "**" = "op_anyone" }
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

run "policy_variable_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "$${aws:username}" = "op_anyone" }
  }

  expect_failures = [var.operators]
}

run "dollar_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "jane$@bank.example" = "op_jane_doe" }
  }

  expect_failures = [var.operators]
}

run "brace_in_user_name_rejected" {
  command = plan

  variables {
    operators = { "{jane}@bank.example" = "op_jane_doe" }
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

# IAM's limit for a customer managed policy is 6,144 characters without whitespace. The validation
# allows 20 operators with 64-character user names and 63-character logins; that policy is larger,
# so the plan fails instead of the apply.
run "policy_size_worst_case_refused" {
  command = plan

  variables {
    operators = { for i in range(20) : format("u%02d%s", i, join("", [for j in range(61) : "a"])) => format("op_u%02d%s", i, join("", [for j in range(57) : "x"])) }
  }

  expect_failures = [aws_iam_policy.connect]
}

# The precondition's edge with the test's region, account and cluster id: 16 user names of 64
# characters and 4 of 63, logins of 24 characters, make a policy of exactly 6,144 characters
# without whitespace, which passes; one more character fails the plan.
run "policy_size_at_the_limit_allowed" {
  command = plan

  variables {
    operators = { for i in range(20) : format("u%02d%s", i, join("", [for j in range(i < 16 ? 61 : 60) : "a"])) => format("op_u%02d%s", i, join("", [for j in range(19) : "x"])) }
  }

  assert {
    condition     = length(replace(aws_iam_policy.connect.policy, "/\\s/", "")) == 6144
    error_message = "This operator map makes a policy of exactly 6,144 characters, which IAM accepts."
  }
}

run "policy_size_one_over_the_limit_refused" {
  command = plan

  variables {
    operators = { for i in range(20) : format("u%02d%s", i, join("", [for j in range(i < 17 ? 61 : 60) : "a"])) => format("op_u%02d%s", i, join("", [for j in range(19) : "x"])) }
  }

  expect_failures = [aws_iam_policy.connect]
}

run "policy_size_twenty_typical_operators" {
  command = plan

  variables {
    operators = { for i in range(20) : format("operator.number%02d@bank.example", i) => format("op_operator_number_%02d", i) }
  }

  assert {
    condition     = length(jsondecode(aws_iam_policy.connect.policy).Statement) == 20 && length(replace(aws_iam_policy.connect.policy, "/\\s/", "")) <= 6144
    error_message = "Twenty operators with e-mail user names fit in one policy."
  }
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
