# Offline docs-consistency check of the audit-table convention (README "Audit
# logging"). The module ships no SQL that creates audit tables; each service's
# migration applies the convention, so the README text is what is pinned here.
#
# pgaudit object audit covers SELECT, INSERT, UPDATE and DELETE only: TRUNCATE
# is never an AUDIT: OBJECT line, and with the default pgaudit.log = ddl,role it
# is not a session line either (class WRITE). The convention therefore grants
# rds_pgaudit UPDATE, DELETE only and refuses TRUNCATE with a statement-level
# BEFORE TRUNCATE trigger set ENABLE ALWAYS (fires under
# session_replication_role = replica too); disabling or dropping it is DDL and
# logged as AUDIT: SESSION class DDL.

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

run "truncate_is_not_claimed_as_object_audited" {
  command = plan

  assert {
    condition     = length(regexall("(?i)GRANT[^;]*TRUNCATE[^;]*TO rds_pgaudit", file("${path.module}/README.md"))) == 0
    error_message = "README: granting TRUNCATE to rds_pgaudit audits nothing (pgaudit object audit has no TRUNCATE); grant UPDATE, DELETE only."
  }

  assert {
    condition     = length(regexall("(?i)GRANT UPDATE, DELETE ON <schema>\\.<audit_table> TO rds_pgaudit;", file("${path.module}/README.md"))) == 1
    error_message = "README: the convention grants rds_pgaudit UPDATE, DELETE on the audit table."
  }

  assert {
    condition     = length(regexall("(?i)or `TRUNCATE` that still happens", file("${path.module}/README.md"))) == 0
    error_message = "README: TRUNCATE never produces an AUDIT: OBJECT line."
  }

  assert {
    condition     = strcontains(file("${path.module}/README.md"), "`TRUNCATE` is not object-audited")
    error_message = "README must say that TRUNCATE is not object-audited."
  }

  assert {
    condition     = !strcontains(file("${path.module}/variables.tf"), "UPDATE, DELETE, TRUNCATE on the audit tables") && strcontains(file("${path.module}/variables.tf"), "TRUNCATE is not object-audited")
    error_message = "variables.tf pgaudit_role description must not claim TRUNCATE is object-audited."
  }
}

run "truncate_refused_by_always_trigger" {
  command = plan

  assert {
    condition     = length(regexall("CREATE TRIGGER <audit_table>_truncate_refused\\s+BEFORE TRUNCATE ON <schema>\\.<audit_table>\\s+FOR EACH STATEMENT EXECUTE FUNCTION <schema>\\.audit_truncate_refused\\(\\);", file("${path.module}/README.md"))) == 1
    error_message = "README: the convention creates a statement-level BEFORE TRUNCATE trigger on the audit table."
  }

  assert {
    condition     = strcontains(file("${path.module}/README.md"), "ALTER TABLE <schema>.<audit_table> ENABLE ALWAYS TRIGGER <audit_table>_truncate_refused;")
    error_message = "README: the TRUNCATE trigger is ENABLE ALWAYS so it fires under session_replication_role = replica."
  }

  assert {
    condition     = length(regexall("CREATE OR REPLACE FUNCTION <schema>\\.audit_truncate_refused\\(\\) RETURNS trigger[^;]*RAISE EXCEPTION", file("${path.module}/README.md"))) == 1
    error_message = "README: give the trigger function that raises."
  }
}

run "drill_checks_truncate" {
  command = plan

  # Check 10 of the Aurora 16 drill: TRUNCATE refused (also under replica),
  # DISABLE TRIGGER logged as AUDIT: SESSION class DDL.
  assert {
    condition = alltrue([
      for needle in ["TRUNCATE", "session_replication_role = replica", "DISABLE TRIGGER", "AUDIT: SESSION", "DDL"] :
      strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 10 must test TRUNCATE (also under replica) and DISABLE TRIGGER as AUDIT: SESSION DDL."
  }
}

# The paragraph after the convention SQL block: what the trigger does not
# cover. Checked on a local PostgreSQL 16.15:
# - the raise function is shared by every audit table in the schema, so
#   CREATE OR REPLACE FUNCTION (no-op body) or DROP FUNCTION ... CASCADE lets
#   TRUNCATE through on all of them with a statement that names no audit table;
# - a statement-level trigger on a partitioned (or inheritance) parent is not
#   cloned to its children, so TRUNCATE of a partition succeeds without DDL,
#   and a REVOKE on the parent does not reach an existing partition either.
run "truncate_bypasses_named" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "CREATE OR REPLACE FUNCTION <schema>.audit_truncate_refused()",
        "DROP FUNCTION <schema>.audit_truncate_refused() CASCADE",
        "names no audit table",
        "any `AUDIT: SESSION` line of class `DDL`",
      ] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: list replacing or dropping the shared raise function among the TRUNCATE bypasses, and make any DDL line outside a migration window the precursor."
  }

  assert {
    condition     = !strcontains(file("${path.module}/README.md"), "naming an audit table is the") && !strcontains(file("${path.module}/README.md"), "Getting past it\nneeds `ALTER TABLE ... DISABLE TRIGGER` or `DROP TRIGGER`") && !strcontains(file("${path.module}/README.md"), "Getting past it needs `ALTER TABLE ... DISABLE TRIGGER` or `DROP TRIGGER`")
    error_message = "README: ALTER TABLE / DROP TRIGGER naming an audit table is not the only TRUNCATE precursor."
  }
}

run "partitioned_audit_tables" {
  command = plan

  assert {
    condition = alltrue([
      for needle in ["partition", "not cloned", "created later", "pg_inherits"] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: a partitioned audit table needs the REVOKE, GRANT and trigger on every partition (statement triggers are not cloned), with a pg_inherits query that finds unguarded children."
  }

  # Offline drill check 4 covers the partition case.
  assert {
    condition = alltrue([
      for needle in ["partition", "pg_inherits", "no rows"] :
      strcontains(one(regex("(?s)\n4\\. (.*?)\n5\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 4 must cover TRUNCATE of a partition and the unguarded-children query."
  }

  # Aurora drill check 10 shows replacing the shared function as a DDL line.
  assert {
    condition     = strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), "CREATE OR REPLACE FUNCTION")
    error_message = "README Aurora 16 drill check 10 must show that replacing the shared raise function is logged as AUDIT: SESSION class DDL."
  }
}
