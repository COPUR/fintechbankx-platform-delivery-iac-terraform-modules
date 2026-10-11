# Offline docs-consistency check of the audit-table convention (README "Audit
# logging"). The module ships no SQL that creates audit tables; each service's
# migration applies the convention, so the README text is what is pinned here.
#
# pgaudit object audit covers SELECT, INSERT, UPDATE and DELETE only: TRUNCATE
# is never an AUDIT: OBJECT line, and with the default pgaudit.log = ddl,role it
# is not a session line either (class WRITE). The convention therefore grants
# rds_pgaudit UPDATE, DELETE only and refuses TRUNCATE with a statement-level
# BEFORE TRUNCATE trigger set ENABLE ALWAYS (fires under
# session_replication_role = replica too); disabling or dropping it is DDL,
# logged as AUDIT: SESSION class DDL when the role cannot turn off audit logging
# for its own session.

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

# pgaudit.log and pgaudit.role are superuser-only settings (on PostgreSQL 16
# also settable by a role granted SET ON PARAMETER on them), and the SET that
# turns logging off is not logged. Checked on a local PostgreSQL 16.15 with pgaudit:
# after SET pgaudit.log = 'none'; SET pgaudit.role = ''; a superuser session's
# DISABLE TRIGGER, CREATE OR REPLACE FUNCTION, TRUNCATE and UPDATE wrote 0
# AUDIT lines, while the owner role got permission denied to set parameter and
# its DISABLE TRIGGER and UPDATE were logged. The master user on Aurora is
# rds_superuser, not a superuser: the drill records whether it can do the same,
# and the README names the compensating control (pre-production gate).
run "superuser_session_bypass_named" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "SET pgaudit.log = 'none'",
        "SET pgaudit.role = ''",
        "permission denied to set parameter",
        "Database Activity Streams",
        "pre-production gate",
        "platform delivery",
        "master_user_secret_arn",
        "secretsmanager.amazonaws.com",
        "GetSecretValue",
        "requestParameters",
        "secretId",
      ] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: name the session that clears its own pgaudit.log and pgaudit.role first, and the compensating control (Database Activity Streams, or the master credential as break-glass with a CloudTrail GetSecretValue alarm) as a pre-production gate owned by platform delivery."
  }

  assert {
    condition = alltrue([
      for needle in ["SET pgaudit.log = 'none'", "SET pgaudit.role = ''", "permission denied to set parameter", "Database Activity Streams", "GetSecretValue"] :
      strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 10 must record whether the master user can change its own pgaudit.log and pgaudit.role, and name the compensating control if it can."
  }


  assert {
    condition = (
      length(regexall("(?i)every way past the trigger\\s+is\\s+DDL\\s+and\\s+logged", file("${path.module}/README.md"))) == 0 &&
      length(regexall("(?i)All of these are logged\\s+as", file("${path.module}/README.md"))) == 0 &&
      length(regexall("\\(owner, DBA\\) an\\s+`AUDIT: OBJECT` line\\.", file("${path.module}/README.md"))) == 0
    )
    error_message = "README must not claim that every way past the trigger, or every UPDATE or DELETE by the owner or DBA, is logged: a session that can turn off its own audit logging gets past it with no log line."
  }
}

# "Non-superuser" is the wrong qualifier for "every way past the trigger is DDL
# and logged". The Aurora master user is not a superuser, yet the README treats
# it as able to turn off its own audit. And on PostgreSQL 16 a NOSUPERUSER role
# granted SET ON PARAMETER pgaudit.log, pgaudit.role gets past the trigger with
# no log line. Checked on a local PostgreSQL 16.15 with pgaudit 16.0: after that
# grant, the owner role's SET pgaudit.log = 'none'; SET pgaudit.role = '';
# DISABLE TRIGGER, TRUNCATE and UPDATE wrote 0 AUDIT lines (the GRANT itself was
# logged once, class ROLE); without it, 2 lines (DDL ALTER TABLE, OBJECT UPDATE).
run "bypass_qualifier_is_who_can_turn_off_audit" {
  command = plan

  assert {
    condition     = length(regexall("(?i)non-superuser\\s+role", file("${path.module}/README.md"))) == 0
    error_message = "README: 'non-superuser role' is the wrong qualifier: the master user is not a superuser, and a NOSUPERUSER role granted SET ON PARAMETER pgaudit.log, pgaudit.role turns off its own audit."
  }

  assert {
    condition     = length(regexall("(?i)every\\s+way\\s+past\\s+the\\s+trigger\\s+by\\s+a\\s+role\\s+that\\s+cannot\\s+turn\\s+off\\s+audit\\s+logging\\s+for\\s+its\\s+own\\s+session\\s+is\\s+DDL\\s+and\\s+logged", one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))))) == 1
    error_message = "README drill check 10: every way past the trigger by a role that cannot turn off audit logging for its own session is DDL and logged."
  }

  assert {
    condition = alltrue([
      for needle in ["superuser", "`rds_superuser`", "`GRANT SET ON PARAMETER`", "`pgaudit.log`", "`pgaudit.role`", "`PUBLIC`"] :
      strcontains(one(regex("(?s)Run\\s+by\\s+a\\s+role\\s+that\\s+cannot\\s+turn\\s+off\\s+audit\\s+logging\\s+for\\s+its\\s+own\\s+session\\s+\\((.*?)\\),\\s+every", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: define a role that cannot turn off audit logging for its own session: not a superuser, not in rds_superuser, no GRANT SET ON PARAMETER on pgaudit.log or pgaudit.role (to it, a role it is in, or PUBLIC)."
  }

  assert {
    condition = alltrue([
      for needle in ["GRANT SET ON PARAMETER pgaudit.log, pgaudit.role TO <owner>", "`NOSUPERUSER`", "class `ROLE`"] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: name the NOSUPERUSER role with GRANT SET ON PARAMETER pgaudit.log, pgaudit.role among the sessions that get past the trigger with no log line (the GRANT is logged once, class ROLE)."
  }
}

# pgaudit.log and pgaudit.role are not the only superuser-only settings that
# keep AUDIT lines out of the log. Checked on a local PostgreSQL 16.15 with
# pgaudit 16.0, pgaudit.log and pgaudit.role left at ddl,role and rds_pgaudit:
# a superuser session's DISABLE TRIGGER, TRUNCATE and UPDATE wrote 0 AUDIT lines
# after SET log_min_messages = 'fatal', and 0 after SET pgaudit.log_client = on;
# SET pgaudit.log_level = 'debug5' (2 with neither). A check that probes only
# the two pgaudit SETs therefore cannot lift the compensating-control gate.
run "other_settings_that_silence_audit" {
  command = plan

  assert {
    condition = alltrue([
      for needle in ["`pgaudit.log_client`", "`pgaudit.log_level`", "`log_min_messages`", "superuser-only setting"] :
      strcontains(one(regex("(?s)Run\\s+by\\s+a\\s+role\\s+that\\s+cannot\\s+turn\\s+off\\s+audit\\s+logging\\s+for\\s+its\\s+own\\s+session\\s+\\((.*?)\\),\\s+every", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: a role that cannot turn off audit logging has no SET grant on any superuser-only setting, log_min_messages, pgaudit.log_client and pgaudit.log_level included."
  }

  assert {
    condition = alltrue([
      for needle in ["SET log_min_messages = 'fatal'", "SET pgaudit.log_client = on", "SET pgaudit.log_level = 'debug5'", "whatever that check shows"] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: name log_min_messages and pgaudit.log_client with pgaudit.log_level as settings that keep AUDIT lines out of the log, and keep the gate whatever drill check 10 shows."
  }

  assert {
    condition = alltrue([
      for needle in ["SET log_min_messages = 'fatal'", "SET pgaudit.log_client = on", "SET pgaudit.log_level = 'debug5'", "whatever they show"] :
      strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 10 must probe log_min_messages and pgaudit.log_client with pgaudit.log_level too, and must not lift the gate."
  }

  assert {
    condition = (
      length(regexall("(?i)If\\s+either\\s+`SET`\\s+succeeds", file("${path.module}/README.md"))) == 0 &&
      length(regexall("(?i)Until\\s+that\\s+check\\s+shows\\s+that\\s+it\\s+cannot", file("${path.module}/README.md"))) == 0
    )
    error_message = "README: the compensating control is a pre-production gate without condition; drill check 10's SETs do not lift it."
  }
}

# Drill check 10 expected the owner role's SETs to fail but ran every step as
# the master user, and did not look for SET ON PARAMETER grants. It now has a
# step run as the owner role and a pg_parameter_acl query. has_parameter_privilege
# sees only inherited grants: on a local PostgreSQL 16.15 a grant to a role the
# owner may only SET ROLE to (INHERIT FALSE, SET TRUE), and a grant on a setting
# outside a fixed list, both gave (0 rows) while the owner turned off its audit.
# The pg_parameter_acl query lists every SET grant on any setting to the owner,
# to any role it is a member of, or to PUBLIC.
run "drill_verifies_owner_cannot_turn_off_audit" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "- as the service's migration (owner) role, in its own session",
        "FROM pg_parameter_acl",
        "aclexplode(a.paracl)",
        "pg_has_role('<owner role>', e.grantee, 'MEMBER')",
        "pg_has_role('<owner role>', 'rds_superuser', 'MEMBER')",
        "(0 rows)",
        "class `ROLE`",
      ] :
      strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 10 must run the SETs as the owner role and list every SET grant reaching it (pg_parameter_acl, any membership) and its rds_superuser membership: (0 rows)."
  }

  assert {
    condition     = !strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), "has_parameter_privilege(")
    error_message = "README drill check 10 must not query has_parameter_privilege: it misses a grant reached by SET ROLE and settings outside a fixed list; list pg_parameter_acl instead."
  }

  assert {
    condition     = length(regexall("(?i)Expected\\s+for\\s+the\\s+service's\\s+migration\\s+\\(owner\\)\\s+role", file("${path.module}/README.md"))) == 0
    error_message = "README drill check 10: the owner role's result is a step of the check, not an expectation no step verifies."
  }

  assert {
    condition     = strcontains(file("${path.module}/README.md"), "The schema owner is meant to be such a role; drill check 10 checks it.")
    error_message = "README: say that drill check 10 checks that the schema owner cannot turn off its own audit logging."
  }
}

# "SET is class MISC, which ddl,role does not log" suggested that adding misc
# would catch the bypass. It does not: pgaudit logs a SET after it has run,
# under the values it leaves. Checked on a local PostgreSQL 16.15 with pgaudit
# 16.0: with pgaudit.log = ddl,role,misc (or all, or ddl,role,misc_set), SET
# pgaudit.log = 'none' and everything after it wrote no line; with misc on,
# SET log_min_messages = 'fatal' and SET pgaudit.log_level = 'debug5' were not
# logged either, while an earlier SET pgaudit.role = '' or SET
# pgaudit.log_client = on was (class MISC).
run "misc_class_does_not_catch_the_set" {
  command = plan

  assert {
    condition     = length(regexall("`SET`\\s+is\\s+class\\s+`MISC`,\\s+which\\s+`ddl,role`\\s+does\\s+not\\s+log", file("${path.module}/README.md"))) == 0
    error_message = "README: do not give 'SET is class MISC, which ddl,role does not log' as the reason: adding misc does not log the SET that turns audit off."
  }

  assert {
    condition = alltrue([
      for needle in ["`misc`", "`misc_set`", "`pgaudit_log_classes`", "is never logged", "does not catch"] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: say that the SET that turns audit logging off is never logged, so adding misc or misc_set to pgaudit_log_classes does not catch it."
  }
}

# "Getting past the trigger takes DDL" does not hold for a superuser, which can
# write the system catalogs. Checked on a local PostgreSQL 16.15 with pgaudit
# 16.0, pgaudit.log and pgaudit.role left at ddl,role and rds_pgaudit, no SET:
# a superuser's UPDATE pg_catalog.pg_trigger SET tgenabled = 'D' and TRUNCATE
# of the audit table wrote 0 AUDIT lines; the NOSUPERUSER owner got permission
# denied for table pg_trigger. Drill check 10 records what the master user gets.
run "catalog_write_bypass_named" {
  command = plan

  assert {
    condition     = length(regexall("(?i)(^|\\n)Getting\\s+past\\s+the\\s+trigger\\s+takes\\s+DDL", file("${path.module}/README.md"))) == 0
    error_message = "README: 'Getting past the trigger takes DDL' needs its qualifier: a superuser disables the trigger with catalog DML."
  }

  assert {
    condition = (
      length(regexall("(?i)any\\s+role\\s+but\\s+a\\s+superuser\\s+\\(below\\),\\s+getting\\s+past", file("${path.module}/README.md"))) == 0 &&
      strcontains(file("${path.module}/README.md"), "For a role that cannot write the system catalogs")
    )
    error_message = "README: qualify 'takes DDL' by catalog write access; the Aurora master user is not a superuser, yet its catalog-DML path is open until drill check 10 shows otherwise."
  }

  assert {
    condition = alltrue([
      for needle in ["UPDATE pg_catalog.pg_trigger SET tgenabled = 'D'", "class `WRITE`", "system catalogs", "permission denied for table pg_trigger"] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: name the superuser's catalog DML (UPDATE pg_catalog.pg_trigger, class WRITE, not logged) and that the Aurora impact rests on rds_superuser having no catalog write access."
  }

  assert {
    condition = alltrue([
      for needle in ["UPDATE pg_catalog.pg_trigger SET tgenabled = 'D'", "permission denied for table pg_trigger"] :
      strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Aurora 16 drill check 10 must record whether the master user can disable the trigger through pg_trigger."
  }
}

# The master credential of a cluster from this module has two uses: the DBA
# bootstrap and the Aurora 16 drill. The products-catalog history guard steps
# run on products' own cluster (an inline aws_rds_cluster in its repository,
# with its own master_user_secret_arn output), not on a cluster from this
# module, so this output must not list them as one of its uses, and must not
# say "for the DBA bootstrap only" either (the drill uses it too).
run "master_secret_output_names_every_use" {
  command = plan

  assert {
    condition = alltrue([
      for needle in ["bootstrap", "drill", "own cluster"] :
      strcontains(one(regex("output \"master_user_secret_arn\" \\{\\s*description\\s*=\\s*\"([^\"]*)\"", file("${path.module}/outputs.tf"))), needle)
    ]) && !strcontains(file("${path.module}/outputs.tf"), "for the DBA bootstrap only") && !strcontains(file("${path.module}/outputs.tf"), "the products-catalog history guard steps and")
    error_message = "outputs.tf master_user_secret_arn: name the bootstrap and the drill as its uses, and say that the products-catalog history guard steps use products' own cluster, not this output."
  }

  assert {
    condition = alltrue([
      for needle in ["bootstrap", "drill", "own cluster"] :
      strcontains(one(regex("\\| `master_user_secret_arn` \\| ([^|\\n]*) \\|", file("${path.module}/README.md"))), needle)
    ]) && !strcontains(file("${path.module}/README.md"), "for the DBA bootstrap only") && !strcontains(file("${path.module}/README.md"), "the products-catalog history guard steps and")
    error_message = "README outputs table master_user_secret_arn: name the bootstrap and the drill as its uses, and say that the products-catalog history guard steps use products' own cluster, not this output."
  }
}

# The break-glass gate passed on one get-secret-value by name, which matches
# only the literal-name value of the secretId list and never evaluates the ARN
# prefix. A wrong prefix (the full ARN, or a trailing "-" left in) would still
# pass, and retrievals by partial ARN would go unalarmed. The gate now calls
# get-secret-value by name, by full ARN and by partial ARN.
run "break_glass_gate_tests_every_secret_id_form" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "--secret-id <master secret name>",
        "--secret-id <master_user_secret_arn>",
        "--secret-id <master_user_secret_arn without its last 7 characters>",
      ] :
      strcontains(one(regex("(?s)\n```\n\nThe default privileges give the runtime role(.*?)\n## TLS to the database", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README: the break-glass gate passes only when get-secret-value by name, by full ARN and by partial ARN each raises the alarm."
  }

  assert {
    condition     = length(regexall("(?i)The\\s+gate\\s+passes\\s+when\\s+one\\s", file("${path.module}/README.md"))) == 0
    error_message = "README: one get-secret-value by name tests only the name value of the secretId pattern, not the ARN prefix."
  }
}

# Round-8 review: the gate had a pass test for one option only, and that option
# watched secret retrieval but not other ways to the master credential.
# AWS documentation (Aurora "Requirements and limitations for Aurora
# Serverless v2"): "The following features from Aurora provisioned DB
# instances currently aren't available for Amazon Aurora serverless: Database
# activity streams (DAS)." This module creates only db.serverless instances,
# so the Activity Streams option is recorded but cannot be chosen here.
run "activity_streams_pass_condition_recorded" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "aws rds describe-db-clusters --db-cluster-identifier <cluster_identifier>",
        "`ActivityStreamStatus`",
        "`started`",
        "`ActivityStreamMode`",
        "`sync`",
        "`ActivityStreamKmsKeyId`",
        "\"eventSource\": [\"rds.amazonaws.com\"]",
        "\"eventName\": [\"StopActivityStream\"]",
        "aws rds stop-activity-stream --resource-arn <non-production cluster ARN>",
        "aren't available for Amazon Aurora serverless",
        "`db.serverless`",
      ] :
      strcontains(one(regex("(?s)\nCompensating control, (.*?)\nPartitioned audit tables:", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README compensating control: give Activity Streams a recorded pass condition (describe-db-clusters status started, mode sync, KMS key), a StopActivityStream alarm with a test call in a non-production account, and say that Aurora Serverless v2 does not support it."
  }

  assert {
    condition     = !strcontains(file("${path.module}/README.md"), "Check first that the cluster's instance class (Serverless v2) and engine version support it in the region.")
    error_message = "README: the Serverless v2 support of Activity Streams is checked against AWS documentation now; do not leave it as an open check."
  }
}

# ModifyDBCluster can set, rotate or unmanage the master password, move it to
# IAM authentication, or re-manage it under another key; none of these is a
# GetSecretValue. CloudTrail records RDS request parameters in lower camel case
# (dBInstanceIdentifier, masterUserPassword) and the password as "****" (AWS
# Aurora user guide, CloudTrail example).
run "break_glass_alarm_covers_master_password_changes" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "\"eventName\": [\"ModifyDBCluster\"]",
        "\"masterUserPassword\": [{ \"exists\": true }]",
        "\"manageMasterUserPassword\": [{ \"exists\": true }]",
        "\"rotateMasterUserPassword\": [{ \"exists\": true }]",
        "\"masterUserSecretKmsKeyId\": [{ \"exists\": true }]",
        "\"masterUserAuthenticationType\": [{ \"exists\": true }]",
        "\"eventName\": [\"EnableHttpEndpoint\"]",
        "\"masterUserPassword\": \"****\"",
        "`dBClusterIdentifier`",
        "not case-sensitive",
        "aws rds modify-db-cluster --db-cluster-identifier <non-production cluster> --rotate-master-user-password --apply-immediately",
        "--no-manage-master-user-password --master-user-password <throwaway password> --apply-immediately",
        "--manage-master-user-password --master-user-secret-kms-key-id <secrets_kms_key_arn> --apply-immediately",
        "--master-user-authentication-type iam-db-auth --apply-immediately",
        "aws rds enable-http-endpoint --resource-arn <non-production cluster ARN>",
      ] :
      strcontains(one(regex("(?s)\nCompensating control, (.*?)\nPartitioned audit tables:", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README break-glass alarm: match ModifyDBCluster with masterUserPassword, manageMasterUserPassword, rotateMasterUserPassword, masterUserSecretKmsKeyId or masterUserAuthenticationType, and EnableHttpEndpoint, and put a master-password change from a non-production account in the gate's test set."
  }
}

# BatchGetSecretValue (AWS Secrets Manager API reference): "Secrets Manager
# generates CloudTrail GetSecretValue log entries for each secret you request
# when you call this action." The CloudTrail entries page also lists a
# BatchGetSecretValue entry. What secretId the per-secret entries carry is not
# documented, so the alarm matches the batch entry too, by id list or filter.
run "break_glass_alarm_covers_batch_retrieval" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "\"eventName\": [\"BatchGetSecretValue\"]",
        "\"secretIdList\": [{ \"prefix\": \"<master_user_secret_arn without its last 7 characters>\" }, \"<master secret name>\"]",
        "\"filters\": { \"key\": [{ \"exists\": true }] }",
        "generates CloudTrail GetSecretValue log entries for each secret you request",
        "aws secretsmanager batch-get-secret-value --secret-id-list <master_user_secret_arn>",
        "aws secretsmanager batch-get-secret-value --filters Key=owning-service,Values=rds",
        "every call",
      ] :
      strcontains(one(regex("(?s)\nCompensating control, (.*?)\nPartitioned audit tables:", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README break-glass alarm: match BatchGetSecretValue (by secretIdList and by filters) as well as the per-secret GetSecretValue entries, and add a batch retrieval to the gate's test set."
  }
}

run "other_paths_covered_or_out_of_scope" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "\"PutResourcePolicy\"",
        "\"ReplicateSecretToRegions\"",
        "RestoreDBClusterFromSnapshot",
        "RestoreDBClusterToPointInTime",
        "ModifyDBClusterParameterGroup",
        "`cloudwatchLogsExportConfiguration`",
        "CreateBlueGreenDeployment",
        "`rds_iam`",
        "Out of scope",
      ] :
      strcontains(one(regex("(?s)\nCompensating control, (.*?)\nPartitioned audit tables:", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README compensating control: cover secret resource-policy and replication changes, and name snapshot restores, parameter-group and log-export changes, blue/green deployments and rds_iam as covered or out of scope with the reason."
  }
}

# The gate result is recorded in the module input pgaudit_bypass_gate; the plan
# of a cluster not marked non-production is refused until it is set
# (tests/pgaudit_bypass_gate.tftest.hcl).
run "gate_record_is_a_module_input" {
  command = plan

  assert {
    condition = alltrue([
      for needle in ["`pgaudit_bypass_gate`", "`drill_run`", "`break-glass`", "refuses to plan", "`Environment`"] :
      strcontains(one(regex("(?s)\nCompensating control, (.*?)\nPartitioned audit tables:", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README compensating control: name pgaudit_bypass_gate (option, drill_run) as where the gate result is recorded, and say which clusters Terraform refuses to plan without it."
  }

  assert {
    condition     = length(regexall("\\| `pgaudit_bypass_gate` \\|", file("${path.module}/README.md"))) == 1 && strcontains(file("${path.module}/variables.tf"), "variable \"pgaudit_bypass_gate\"")
    error_message = "pgaudit_bypass_gate is a module input (variables.tf) listed in the README Inputs table."
  }

  assert {
    condition     = strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), "`pgaudit_bypass_gate`")
    error_message = "README Aurora 16 drill check 10 must point at pgaudit_bypass_gate, where the gate result is recorded."
  }
}

# The drill_run validation checks the form only: "<drill run>", "TBD" and
# "https://TBD" are refused, a well-formed link or id that names no drill run
# is not (tests/pgaudit_bypass_gate.tftest.hcl). The README must not claim that
# placeholder records in general are refused.
run "drill_run_check_is_form_only" {
  command = plan

  assert {
    condition     = !strcontains(file("${path.module}/README.md"), "placeholder records are refused")
    error_message = "README Tests: the drill_run validation refuses some placeholders (<drill run>, TBD, https://TBD), not every placeholder record."
  }

  assert {
    condition = alltrue([
      for needle in ["only the form of `drill_run`", "`https://TBD`", "reviewer of the plan"] :
      strcontains(one(regex("(?s)\nWhere the result is recorded: (.*?)\n\n", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Where the result is recorded: say that Terraform checks only the form of drill_run (https://TBD refused, a well-formed link or id is not looked up) and that the reviewer of the plan checks the record."
  }
}

# The gate record and the plan refusal act only on clusters this module
# creates. A service that defines its own aws_rds_cluster is outside them:
# nothing records its gate result and nothing refuses its production plan.
# When this was written, every service with an Aurora cluster did that and
# none called this module, products-catalog included, the only one that
# preloads pgaudit and carries the history guard. The README must say so and
# must not tie the history guard to this module's master credential or to
# pgaudit_bypass_gate.
run "gate_scope_is_clusters_from_this_module" {
  command = plan

  assert {
    condition = alltrue([
      for needle in [
        "only on clusters this module creates",
        "defines its own `aws_rds_cluster`",
        "outside this gate",
        "nothing refuses its production plan",
        "products-catalog",
        "same precondition",
      ] :
      strcontains(one(regex("(?s)\nWhere the result is recorded: (.*?)\n\n", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README Where the result is recorded: say that the record and the refusal act only on clusters from this module, and that a service cluster defined inline (products-catalog included) is outside the gate until it moves to the module or carries the same precondition."
  }

  assert {
    condition     = length(regexall("every use \\([^)]*history guard", file("${path.module}/README.md"))) == 0
    error_message = "README break-glass: the products-catalog history guard steps run on products' own cluster, not on a cluster from this module; do not list them as a use of this module's master credential."
  }

  assert {
    condition     = strcontains(one(regex("(?s)\n10\\. (.*?)\n11\\. ", file("${path.module}/README.md"))), "recorded in `pgaudit_bypass_gate` for a cluster from this module")
    error_message = "README drill check 10: the gate result is recorded in pgaudit_bypass_gate only for a cluster from this module, not for products' own cluster."
  }
}

# AWS (Aurora User Guide, blue/green considerations): "Blue/green deployments
# don't support managing master user passwords with AWS Secrets Manager." The
# Secrets Manager limitations page lists "Amazon RDS Blue/Green Deployments"
# as well. This module always sets manage_master_user_password = true, so on
# its clusters CreateBlueGreenDeployment first needs ModifyDBCluster with
# manageMasterUserPassword false (and a masterUserPassword), which the cluster
# rule matches. It is not an IAM path that bypasses the alarm on its own.
run "blue_green_needs_unmanaged_master_password" {
  command = plan

  assert {
    condition     = !strcontains(one(regex("(?s)\n  - the cluster's audit configuration (.*?);\n", file("${path.module}/README.md"))), "CreateBlueGreenDeployment")
    error_message = "README out of scope: CreateBlueGreenDeployment is not available on a cluster from this module while RDS manages the master password; do not list it with the IAM paths that switch off pgaudit without that condition."
  }

  assert {
    condition = alltrue([
      for needle in [
        "don't support managing master user passwords with AWS Secrets Manager",
        "`manage_master_user_password = true`",
        "`manageMasterUserPassword` false",
        "the cluster rule",
      ] :
      strcontains(one(regex("(?s)\n  - `CreateBlueGreenDeployment`(.*?);\n", file("${path.module}/README.md"))), needle)
    ])
    error_message = "README compensating control: say that blue/green deployments do not support RDS-managed master passwords, which this module always turns on, so the path first takes ModifyDBCluster with manageMasterUserPassword false, which the cluster rule matches."
  }
}
