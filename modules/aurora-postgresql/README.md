# aurora-postgresql

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Aurora PostgreSQL Serverless v2 owned by exactly one service (database per
service). Generalises what loan-lifecycle-core's deploy/terraform does
inline: dedicated KMS keys (storage and secrets, ADR-023), rds.force_ssl, subnet group across AZs, a
security group that only admits the workload security group(s), an
RDS-managed admin credential, an application credential secret container
(value written by the DBA bootstrap, never by Terraform) and alarms.
Also used for the Keycloak database (no separate module).

## Usage

```hcl
module "aurora_postgresql" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/aurora-postgresql?ref=main"
  # inputs below
}
```

Examples: [`examples/aurora-postgresql`](../../examples/aurora-postgresql/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Resource name prefix, normally <env>-<service-slug> (e.g. dev-loan-lifecycle-service). |
| `database_name` | `string` | required | Initial database, db_<ctx>_<capability>_<env> (e.g. db_ln_loan_lifecycle_dev). |
| `master_username` | `string` | required | Admin user name; its credential is generated and stored by RDS in Secrets Manager. |
| `engine_version` | `string` | `"16.4"` | Aurora PostgreSQL engine version. |
| `instance_count` | `number` | `2` | Writer plus readers. 2+ puts a reader in another AZ for failover; use 2+ outside dev. |
| `min_capacity` | `number` | `0.5` | Serverless v2 minimum ACUs. |
| `max_capacity` | `number` | `8` | Serverless v2 maximum ACUs. |
| `vpc_id` | `string` | required | VPC id. |
| `subnet_ids` | `list(string)` | required | Private or intra subnets in at least two AZs. |
| `allowed_security_group_ids` | `list(string)` | required | Security groups allowed to connect on 5432 (EKS cluster/node or pod security group). |
| `kms_key_arn` | `string` | `null` | Storage key override (cluster storage, snapshots, Performance Insights); must not carry `fintechbankx.io/secrets`. null creates `<name>-db-storage`. |
| `secrets_kms_key_arn` | `string` | `null` | Secrets key override (master, db-app, db-migration secrets), tagged `fintechbankx.io/secrets=true`, different from `kms_key_arn`. null creates `<name>-db-secrets`. |
| `iam_database_authentication_enabled` | `bool` | `true` | Enable IAM database authentication. |
| `backup_retention_days` | `number` | `35` | Automated backup retention (PITR window). |
| `preferred_backup_window` | `string` | `"01:00-02:00"` | Daily backup window (UTC). |
| `preferred_maintenance_window` | `string` | `"sun:03:00-sun:04:00"` | Weekly maintenance window (UTC). |
| `deletion_protection` | `bool` | `true` | Protect the cluster from deletion. |
| `performance_insights_retention_days` | `number` | `7` | Performance Insights retention (7 is free tier). |
| `log_min_duration_statement_ms` | `number` | `500` | Log statements slower than this many milliseconds. |
| `create_app_secret` | `bool` | `true` | Create the empty application credential secret. |
| `app_secret_name` | `string` | required | Application credential secret name, `<env>/<service-slug>/<name>` (usually `db-app`), so only the service's own ExternalSecret can sync it. The migration secret defaults to the same directory. |
| `alarm_topic_arn` | `string` | `null` | SNS topic for alarms; null disables notifications. |
| `acu_alarm_threshold_percent` | `number` | `85` | ACUUtilization alarm threshold. |
| `connections_alarm_threshold` | `number` | `100` | DatabaseConnections alarm threshold. |
| `tags` | `map(string)` | `{}` | Resource tags. |
| `observability_discovery` | `bool` | `true` | Tag resources fintechbankx.io/observability=enabled so the YACE CloudWatch exporter discovers them. |
| `pgaudit_enabled` | `bool` | `true` | Preload `pgaudit` and set `pgaudit.log`. |
| `pgaudit_log_classes` | `list(string)` | `["ddl", "role"]` | `pgaudit.log` classes. |
| `pgaudit_role` | `string` | `"rds_pgaudit"` | `pgaudit.role` (object audit); created by `role_bootstrap_sql` if missing. |
| `schema_name` | `string` | `null` | Service schema `sc_<ctx>_<cap>`; with the two role names renders `role_bootstrap_sql`. |
| `app_role_name` | `string` | `null` | Runtime role (pods): `USAGE` + DML only. |
| `migration_role_name` | `string` | `null` | Schema-owner role (Flyway only); must differ from `app_role_name`. |
| `ssl_root_cert_path` | `string` | `"/etc/fintechbankx/rds-ca/global-bundle.pem"` | Path of the RDS CA bundle in the container, used by `sslmode=verify-full` in the JDBC URL outputs. |

## Outputs

| Name | Description |
|---|---|
| `cluster_identifier` | Aurora cluster identifier. |
| `cluster_arn` | Aurora cluster ARN. |
| `cluster_resource_id` | Cluster resource id (for rds-db:connect IAM policies). |
| `endpoint` | Writer endpoint. |
| `reader_endpoint` | Reader endpoint. |
| `port` | PostgreSQL port. |
| `jdbc_url` | Writer JDBC URL with `sslmode=verify-full&sslrootcert=<ssl_root_cert_path>` (Helm value config.DB_URL). |
| `reader_jdbc_url` | Reader JDBC URL with the same certificate verification. |
| `ssl_root_cert_path` | Container path of the RDS CA bundle the URLs trust. |
| `migration_secret_arn` / `migration_secret_name` | Schema-owner (Flyway) credential secret. |
| `role_bootstrap_sql` | DBA bootstrap SQL of the two-role pattern, or null. |
| `security_group_id` | Database security group. |
| `kms_key_arn` | Storage key (ADR-023). Workloads never need it. |
| `secrets_kms_key_arn` | Secrets key (ADR-023) of every Secrets Manager secret of the database; pass it to `operator-db-access` `kms_key_arns` (stack variable `operator_db_import_kms_key_arns`). |
| `app_secret_arn` | Application credential secret ARN. |
| `app_secret_name` | Application credential secret name (Helm value externalSecret.remoteSecretName). |
| `master_user_secret_arn` | RDS-managed admin credential, for the DBA bootstrap only. |

## Tests

`terraform test` (Terraform >= 1.7, mock AWS provider, no credentials) in [`tests/`](tests): `rds.force_ssl=1`, storage encrypted, deletion protection on, rotating CMK, observability tag; reserved user rejected; JDBC URLs use `sslmode=verify-full` with the mounted CA bundle (`tls_verify_full.tftest.hcl`, `command = apply` against the mock provider); KMS split (`kms_split.tftest.hcl`: storage key untagged, every secret on the secrets key, one key for both rejected); PostgreSQL 16 bootstrap order and `pgaudit.role` (`role_bootstrap.tftest.hcl`, `pgaudit.tftest.hcl`).
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.

## Encryption keys (ADR-023)

Two rotating customer managed keys per database:

| Key (alias) | Encrypts | Tag `fintechbankx.io/secrets` | Override |
|---|---|---|---|
| `<name>-db-storage` | cluster storage, snapshots, Performance Insights | no | `kms_key_arn` |
| `<name>-db-secrets` | RDS-managed master secret, `db-app`, `db-migration` (and the operator `db-import` secret through `operator-db-access`) | `true` | `secrets_kms_key_arn` |

The External Secrets roles may decrypt only with keys tagged `fintechbankx.io/secrets=true` and only through Secrets
Manager, so they can read the credential secrets they are allowed to read but never use the storage key. Neither key
policy names External Secrets (default key policy: the account administers the key, IAM grants use). Outputs
`kms_key_arn` (storage) and `secrets_kms_key_arn`. Passing the same ARN for both is rejected.

Migration note: before this split the module created one tagged key (`alias/<name>-db`) for both. No cluster is
deployed from this module yet; an existing state would replace the alias and move the secrets to the new key on the
next apply, which needs a planned change window.

## Audit logging (pgaudit)

The cluster parameter group preloads `pg_stat_statements,pgaudit` (`shared_preload_libraries`, `apply_method =
pending-reboot`; setting the parameter replaces the Aurora default, so `pg_stat_statements` is kept) and sets
`pgaudit.log = ddl,role` by default, so schema changes (Flyway as the owner role) and role or grant changes reach the
`postgresql` log export in CloudWatch. No cluster is deployed yet, so the default costs nothing now; **enabling it on an
existing cluster needs a reboot of every instance** before `shared_preload_libraries` takes effect. Statement classes
are configurable (`pgaudit_log_classes`); `read`/`write` log data access and can include personal data in statements.
Register the extension once per database (`CREATE EXTENSION pgaudit;`) as part of the DBA bootstrap.

Object audit: the parameter group sets `pgaudit.role = rds_pgaudit` (`pgaudit_role`), and `role_bootstrap_sql` creates
that role if it does not exist (an idempotent `DO` block). pgaudit then logs every statement on an object
`rds_pgaudit` holds a privilege on, as `AUDIT: OBJECT`, independently of `pgaudit.log`.

This module only creates the `rds_pgaudit` role and sets `pgaudit.role`; it never grants anything on any table
(`tests/role_bootstrap.tftest.hcl` `bootstrap_grants_nothing_on_tables`). Object-audit grants come from each service's
own migrations or code. Example: products grants them from its history guard's `arm()` (`UPDATE, DELETE` on
`product_history`, `INSERT, UPDATE, DELETE` on `fbx_history_guard.armed` and `fbx_history_guard.event`).

Migration convention for audit tables (in the service's migration that creates the table, as the owner role):

```sql
GRANT UPDATE, DELETE, TRUNCATE ON <schema>.<audit_table> TO rds_pgaudit;   -- object audit of any change
REVOKE UPDATE, DELETE ON <schema>.<audit_table> FROM <app_role>;           -- runtime role: INSERT and SELECT only
```

The default privileges give the runtime role `UPDATE, DELETE`; the `REVOKE` makes the audit table append-only for the
pods, and the `GRANT` makes any `UPDATE`, `DELETE` or `TRUNCATE` that still happens (owner, DBA) an `AUDIT: OBJECT`
line. Log alarms (CloudWatch metric filters on the `postgresql` log group, owned by the observability repository)
should match `AUDIT: OBJECT` on the audit tables and `AUDIT: SESSION` lines of class `DDL` (and `ROLE`) outside a
migration window.

## TLS to the database (verify-full)

`rds.force_ssl=1` makes the server refuse plaintext, but `sslmode=require` on the client still trusts any certificate. The
JDBC URL outputs therefore use `sslmode=verify-full`: pgjdbc checks that the server certificate chains to the Amazon RDS
CA and names the endpoint. The CA bundle reaches the pod from the platform: the mesh repository's trust-manager Bundle
publishes ConfigMap `rds-ca-bundle` (key `global-bundle.pem`) in every service namespace, and the `fintechbankx-service`
chart (cicd-templates) mounts it read-only at `/etc/fintechbankx/rds-ca`. A service with its own chart mounts the same
ConfigMap at the same path or sets `ssl_root_cert_path`.

## Database roles (two-role pattern)

Each service database has two roles, created by the DBA bootstrap:

| Role | Secret (this module creates the empty container) | Used by | Grants |
|---|---|---|---|
| Schema owner | `<env>/<service-slug>/db-migration` (`migration_secret_name`) | Flyway only (migration step or Job) | owns `sc_<ctx>_<cap>`; DDL |
| Runtime | `<env>/<service-slug>/db-app` (`app_secret_name`) | the service pods (`DB_USERNAME`/`DB_PASSWORD`) | only the DML the service needs (e.g. SELECT, INSERT) |

`role_bootstrap_sql` (set `schema_name`, `app_role_name` and `migration_role_name`) renders the DBA bootstrap for these
roles: the owner role owns `sc_<ctx>_<cap>` and runs Flyway; the runtime role gets `USAGE` on the schema and, through
`ALTER DEFAULT PRIVILEGES FOR ROLE <owner>`, only `SELECT, INSERT, UPDATE, DELETE` on tables (and `USAGE, SELECT` on
sequences) that Flyway creates: no DDL, no `TRUNCATE`, no ownership. The SQL carries no password; the DBA sets each
one with `\password` from its secret. `tests/role_bootstrap.tftest.hcl` pins these grants.

On PostgreSQL 16 the RDS admin is a `CREATEROLE` member of `rds_superuser`, not a superuser, and a role it creates is
granted back to it with `ADMIN` only (no `SET`, no `INHERIT`). The SQL therefore runs
`GRANT <owner> TO CURRENT_USER WITH SET TRUE, INHERIT FALSE`, `CREATE SCHEMA ... AUTHORIZATION <owner>`,
`SET ROLE <owner>`, the `GRANT USAGE` and both `ALTER DEFAULT PRIVILEGES`, `RESET ROLE` and
`REVOKE <owner> FROM CURRENT_USER`: the admin acts as the owner only for those statements and keeps no `SET` membership
afterwards. Engines before 16 get a plain `GRANT <owner> TO CURRENT_USER` (no `SET` option there). Example (request to pay):
`schema_name = "sc_pay_request_to_pay"`, `app_role_name = "payment_request_to_pay_app"`,
`migration_role_name = "payment_request_to_pay_migration"`.

Migration step convention: Flyway runs as a Kubernetes Job (or CI step) with the db-migration secret, never in the
service pods (`spring.flyway.enabled=false` there, no `create-schemas`). Job pods carry `app.kubernetes.io/name=<sa>`
(the mesh grants Aurora egress on that label) and `app.kubernetes.io/component=db-migration`; service pods carry
`app.kubernetes.io/component=service`, and the `fintechbankx-service` chart selects only those. Both use the JDBC URL
outputs (`sslmode=verify-full`) and mount the RDS CA bundle (section above).

Both secrets hold `{"username", "password"}` and are read through the `aws-secrets-manager` ClusterSecretStore. Keep the owner credential out of the long-running pods: run Flyway as a separate step with the db-migration secret. Both are tagged `fintechbankx.io/value-in-state = false` after `var.tags` is merged, so no caller tag can make them readable by the pull-request `tf-plan` role (`github-oidc`).


## Aurora 16 drill (bootstrap)

Run before the first service bootstrap on a new engine major, and after any change to `role_bootstrap_sql`.

Offline, on a local PostgreSQL 16 (what the review of PR #11 used): start a throwaway cluster, create an admin
`LOGIN CREATEROLE CREATEDB NOSUPERUSER` that owns the service database (as on RDS), render the SQL with
`terraform console` (`local.role_bootstrap_sql`) and run it as that admin with `psql -v ON_ERROR_STOP=1`. Leave out
the `CREATE EXTENSION pgaudit` line if the local server has no pgaudit. Expected:

1. the bootstrap completes; the schema owner is the migration role;
2. `pg_auth_members` shows the admin in the owner role with `admin_option` only (`set_option = false`), and
   `SET ROLE <owner>` as the admin is denied;
3. as the owner, `CREATE TABLE` in the schema works; as the runtime role, `INSERT`/`UPDATE` on it work (default
   privileges) while `CREATE TABLE` in the schema or in `public` and `TRUNCATE` are denied;
4. after the audit-table convention above, the runtime role can `INSERT` but not `UPDATE` the audit table;
5. re-running the `rds_pgaudit` `DO` block succeeds.

Two more checks, run as the RDS master user, for services whose migrations need them:

6. `SET session_replication_role = replica;` succeeds. This needs `rds_superuser` on Aurora; a plain `CREATEROLE`
   user on a local PostgreSQL 16 is denied (`permission denied to set parameter`), so run this check on Aurora only.
7. `GRANT <role created by someone else> TO <role> WITH INHERIT TRUE, SET TRUE;` succeeds only if the master user holds
   `ADMIN OPTION` on the granted role. PostgreSQL 16 no longer lets `CREATEROLE` grant any role: without it the
   statement fails with `permission denied to grant role` and `Only roles with the ADMIN option on role ... may grant
   this role` (seen on a local PostgreSQL 16.15; it succeeds once `ADMIN OPTION` is granted). Record which result
   Aurora gives for the roles the service needs.

Checks for the products-catalog history guard, run as the RDS master user on Aurora 16:

8. `rds_superuser` grants a role `WITH INHERIT TRUE, SET TRUE` to another role: succeeds only with `ADMIN OPTION` on
   the granted role.
9. An `ENABLE ALWAYS` trigger fires while `session_replication_role = replica`, and an ordinary (`ENABLE`) trigger does
   not: expected, the `ALWAYS` trigger fires and the ordinary trigger is skipped.
10. With `pgaudit.role = rds_pgaudit` and an object grant to `rds_pgaudit` on a test table, an `UPDATE` on that table
    writes an `AUDIT: OBJECT` line to the PostgreSQL log: expected, the line is present in CloudWatch.
11. The master user can `CREATE EVENT TRIGGER`: expected, it succeeds as `rds_superuser` on Aurora PostgreSQL 16.
12. No writer membership is left after the master user arms the guard or hands the writer back. The master user is
    not a superuser, so `set_history_writer()` grants it the schema owner and `open_products_catalog_history_writer`
    `WITH INHERIT TRUE, SET TRUE` for the transfer only and revokes both before it returns. Run this as the master
    user after each step below:

    ```sql
    SELECT r.rolname AS granted_role, a.rolname AS member, m.admin_option, m.inherit_option, m.set_option
      FROM pg_auth_members m
      JOIN pg_roles r ON r.oid = m.roleid
      JOIN pg_roles a ON a.oid = m.member
     WHERE r.rolname IN ('open_products_catalog_history_writer', 'open_products_catalog_owner')
       AND a.rolname = current_user
       AND (m.inherit_option OR m.set_option);
    ```

    Expected: `(0 rows)` every time. Without the last line, the query shows only the creator's grant on each role
    (`admin_option = t`, `inherit_option = f`, `set_option = f`). The steps:
    - arm path: `SELECT fbx_history_guard.arm('<ticket>');` returns `armed, intact`;
    - hand-back path: `disarm('<ticket>')`, then `hand_back_history_writer('<ticket>')`, then `arm('<ticket>')`. Run
      the query after the hand-back and again after the arm;
    - failed arm: while disarmed, grant the writer to a scratch role `WITH INHERIT TRUE, SET FALSE`. `arm()` then
      fails after the transfer with `cannot arm, <role> (granted by ...) can act as
      open_products_catalog_history_writer`. Revoke the grant and drop the scratch role afterwards;
    - failed or interrupted transfer, for both `arm` and `hand_back_history_writer`, while disarmed: as the schema
      owner, open a second session and hold the history table's catalog row with
      `BEGIN; GRANT SELECT ON sc_of_open_products_catalog.product_history TO open_products_catalog_owner;`, leaving
      the transaction open. In the master session, either `SET lock_timeout = '1s'` before the call, which then fails
      with `canceling statement due to lock timeout`, or leave the call blocked and end it from a third session, as
      the master user and in the same database (use `hand_back_history_writer(` in the pattern for the hand-back):

      ```sql
      SELECT pid, pg_terminate_backend(pid)
        FROM pg_stat_activity
       WHERE datname = current_database()
         AND usename = current_user
         AND state = 'active'
         AND wait_event_type = 'Lock'
         AND query LIKE '%fbx_history_guard.arm(%'
         AND pid <> pg_backend_pid();
      ```

      Expected: one row, with `t`. `pg_stat_activity` keeps the last statement of idle sessions and lists every
      database, so the filters keep a finished `arm()` in an idle session, or a session elsewhere on the cluster, from
      being ended. `(0 rows)` means no call was blocked and nothing was ended: check the owner session and run it again.
      `ROLLBACK` the owner session. Each call runs as one transaction, so the temporary grants roll back with it, and
      `verify()` still returns `DISARMED` until an `arm` succeeds.
13. The guard's catalog lookups work without `USAGE` on the service schema. As the master user, check that it holds
    none: `SELECT has_schema_privilege('sc_of_open_products_catalog', 'USAGE');` returns `f`. If it returns `t`, list
    where the `USAGE` comes from:

    ```sql
    SELECT coalesce(g.rolname, 'PUBLIC') AS usage_from, 'schema ACL' AS via
      FROM pg_namespace n
     CROSS JOIN aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      LEFT JOIN pg_roles g ON g.oid = a.grantee
     WHERE n.nspname = 'sc_of_open_products_catalog'
       AND a.privilege_type = 'USAGE'
       AND (a.grantee = 0 OR pg_has_role(current_user, a.grantee, 'USAGE'))
    UNION ALL
    SELECT r.rolname, 'predefined role'
      FROM pg_roles r
     WHERE r.rolname IN ('pg_read_all_data', 'pg_write_all_data')
       AND pg_has_role(current_user, r.oid, 'USAGE');
    ```

    Each row is one source, and each needs its own fix; `REVOKE ... FROM <master user>` removes only the first:
    - the master user itself: the schema owner runs `REVOKE USAGE ON SCHEMA sc_of_open_products_catalog FROM <master
      user>`;
    - `PUBLIC`: the schema owner runs `REVOKE USAGE ON SCHEMA sc_of_open_products_catalog FROM PUBLIC` (the bootstrap
      grants `USAGE` to the runtime role only);
    - the schema owner, or another role the master user inherits: revoke that membership (a leftover owner membership
      is the one check 12 looks for);
    - `pg_read_all_data` or `pg_write_all_data`: either gives `USAGE` on every schema. Revoke it from whichever role
      the master user inherits it through. If Aurora gives it through `rds_superuser` and it cannot be revoked, record
      that: the master user then always has `USAGE`, this check cannot be run on that cluster, and the offline run
      below is the evidence for it.

    Run the query again until it returns `(0 rows)` and `has_schema_privilege` returns `f`. Then run this probe on its
    own, outside a transaction and without `ON_ERROR_STOP`, because it is expected to fail:

    ```sql
    SELECT to_regclass('sc_of_open_products_catalog.product_history');
    ```

    Expected: `ERROR: permission denied for schema sc_of_open_products_catalog`. If it returns the table instead, the
    master user still has `USAGE`; do not go on, because the rest of the check would pass without testing anything.
    Then, still as the master user and with the guard disarmed, so that `arm()` runs its lookups as well
    (`disarm('<ticket>')` first if `verify()` returns `armed, intact`; `arm()` on an armed guard raises
    `already armed`):

    ```sql
    SELECT fbx_history_guard.table_oid('product_history') IS NOT NULL,
           fbx_history_guard.table_oid('product') IS NOT NULL,
           fbx_history_guard.function_oid('product_history_record') IS NOT NULL,
           fbx_history_guard.function_oid('product_history_append_only') IS NOT NULL,
           fbx_history_guard.function_oid('product_history_insert_guard') IS NOT NULL,
           fbx_history_guard.function_oid('product_truncate_refused') IS NOT NULL,
           (SELECT fingerprint FROM fbx_history_guard.current_state()) IS NOT NULL;  -- t for every column
    SELECT fbx_history_guard.arm('<ticket>');  -- armed, intact
    SELECT fbx_history_guard.verify();         -- armed, intact
    SELECT has_schema_privilege('sc_of_open_products_catalog', 'USAGE');  -- still f
    ```

    `table_oid()` and `function_oid()` read `pg_class` and `pg_proc` joined to `pg_namespace`. `verify()` reads
    `pg_event_trigger` and `pg_trigger`. None of these needs `USAGE` on the schema. Run `verify()` again as the
    runtime role, which is the credential the history-guard CronJob uses: expected, `armed, intact`.

The SQL from before the PostgreSQL 16 change fails at step 1 with `must be able to SET ROLE "<owner>"`.

Checks 12 and 13 also run offline on a local PostgreSQL 16 against products' `db/bootstrap/history-guard.sql`:
- create a `CREATEROLE` admin and run the bootstrap above as that admin;
- apply the service migrations as the schema owner;
- run the guard file as the admin, without its `CREATE EVENT TRIGGER` and `DROP EVENT TRIGGER` lines, then create
  the two event triggers as a superuser. On Aurora the master user does this itself (check 11).

Locally the guard file's `ALTER ROLE ... NOSUPERUSER` is refused for a non-superuser with `Only roles with the
SUPERUSER attribute may change the SUPERUSER attribute`, so drop `NOSUPERUSER` from that line locally. On Aurora,
record whether the master user hits the same error.

On Aurora 16 (dev, once per engine major): the same steps against a scratch database in the dev cluster, connected
through the operator path (`stacks/platform` README, "Operator database access"); with pgaudit loaded, check that the
`GRANT`/`REVOKE` lines appear as `AUDIT: SESSION` class `ROLE` and the `CREATE SCHEMA` as class `DDL` in the
`postgresql` log group, and that an `UPDATE` on an audit table by the owner logs `AUDIT: OBJECT`. Record the run
(date, engine version, log excerpts without credentials) in the PR or the change record.
