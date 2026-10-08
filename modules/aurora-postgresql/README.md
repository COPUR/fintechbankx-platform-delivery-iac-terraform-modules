# aurora-postgresql

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Aurora PostgreSQL Serverless v2 owned by exactly one service (database per
service). Generalises what loan-lifecycle-core's deploy/terraform does
inline: dedicated KMS key, rds.force_ssl, subnet group across AZs, a
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
| `kms_key_arn` | `string` | `null` | Existing KMS key. null creates a dedicated key with rotation. |
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
| `kms_key_arn` | KMS key protecting storage and credentials (grant kms:Decrypt to the workload). |
| `app_secret_arn` | Application credential secret ARN. |
| `app_secret_name` | Application credential secret name (Helm value externalSecret.remoteSecretName). |
| `master_user_secret_arn` | RDS-managed admin credential, for the DBA bootstrap only. |

## Tests

`terraform test` (Terraform >= 1.7, mock AWS provider, no credentials) in [`tests/`](tests): `rds.force_ssl=1`, storage encrypted, deletion protection on, rotating CMK, observability tag; reserved user rejected; JDBC URLs use `sslmode=verify-full` with the mounted CA bundle (`tls_verify_full.tftest.hcl`, `command = apply` against the mock provider).
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.

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
one with `\password` from its secret. `tests/role_bootstrap.tftest.hcl` pins these grants. Example (request to pay):
`schema_name = "sc_pay_request_to_pay"`, `app_role_name = "payment_request_to_pay_app"`,
`migration_role_name = "payment_request_to_pay_migration"`.

Migration step convention: Flyway runs as a Kubernetes Job (or CI step) with the db-migration secret, never in the
service pods (`spring.flyway.enabled=false` there, no `create-schemas`). Job pods carry `app.kubernetes.io/name=<sa>`
(the mesh grants Aurora egress on that label) and `app.kubernetes.io/component=db-migration`; service pods carry
`app.kubernetes.io/component=service`, and the `fintechbankx-service` chart selects only those. Both use the JDBC URL
outputs (`sslmode=verify-full`) and mount the RDS CA bundle (section above).

Both secrets hold `{"username", "password"}` and are read through the `aws-secrets-manager` ClusterSecretStore. Keep the owner credential out of the long-running pods: run Flyway as a separate step with the db-migration secret. Both are tagged `fintechbankx.io/value-in-state = false` after `var.tags` is merged, so no caller tag can make them readable by the pull-request `tf-plan` role (`github-oidc`).

