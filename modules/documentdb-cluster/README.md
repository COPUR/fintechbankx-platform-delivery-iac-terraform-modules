# documentdb-cluster

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Amazon DocumentDB cluster owned by exactly one service (open finance data
services). Instances spread across AZs, KMS encryption at rest, TLS forced
by the cluster parameter group, audit and profiler logs to CloudWatch, a
security group that admits only the workload security group(s), backups
with PITR, and two Secrets Manager entries:
- <name>/docdb-master        admin credential for the DBA bootstrap only
(deliberately outside <env>/* so the cluster
secret store cannot sync it)
- <env>/<slug>/docdb-app     application credential container; the DBA
bootstrap creates the app user and writes it
Provider 5.x has no RDS-managed master secret for DocumentDB, so the admin
credential is generated here and therefore present in (encrypted) state.

## Usage

```hcl
module "documentdb_cluster" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/documentdb-cluster?ref=main"
  # inputs below
}
```

Examples: [`examples/documentdb-cluster`](../../examples/documentdb-cluster/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`
- `hashicorp/random` `>= 3.6`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | dev, staging or prod (secret names start with it). |
| `service_slug` | `string` | required | Service slug / Kubernetes service account (e.g. personal-financial-data-service). |
| `name` | `string` | `null` | Resource name prefix. null uses <environment>-<service_slug>. |
| `engine_version` | `string` | `"5.0.0"` | DocumentDB engine version. |
| `engine_major_version` | `string` | `"5.0"` | Parameter group family suffix (docdb<major>). |
| `instance_class` | `string` | `"db.r6g.large"` | Instance class. |
| `instance_count` | `number` | `3` | Instances (primary + replicas). 3 spreads one per AZ; use >= 2 outside dev. |
| `master_username` | `string` | `"docdb_admin"` | Admin user name. |
| `vpc_id` | `string` | required | VPC id. |
| `subnet_ids` | `list(string)` | required | Private subnets in at least two AZs (three recommended). |
| `allowed_security_group_ids` | `list(string)` | required | Security groups allowed on 27017. |
| `kms_key_arn` | `string` | `null` | Storage key override (cluster storage, snapshots); must not carry `fintechbankx.io/secrets`. null creates `<name>-docdb-storage`. |
| `secrets_kms_key_arn` | `string` | `null` | Secrets key override (`docdb-master`, `docdb-app`), tagged `fintechbankx.io/secrets=true`, different from `kms_key_arn`. null creates `<name>-docdb-secrets`. |
| `backup_retention_days` | `number` | `35` | Backup retention / PITR window. |
| `deletion_protection` | `bool` | `true` | Protect the cluster from deletion. |
| `profiler_threshold_ms` | `number` | `200` | Profile operations slower than this. |
| `connections_alarm_threshold` | `number` | `500` | DatabaseConnections alarm threshold. |
| `alarm_topic_arn` | `string` | `null` | SNS topic for alarms; null disables notifications. |
| `tags` | `map(string)` | `{}` | Resource tags. |
| `observability_discovery` | `bool` | `true` | Tag resources fintechbankx.io/observability=enabled so the YACE CloudWatch exporter discovers them. |

## Outputs

| Name | Description |
|---|---|
| `endpoint` | Cluster (writer) endpoint. |
| `reader_endpoint` | Reader endpoint. |
| `port` | Port. |
| `connection_options` | Driver options the app must use (TLS with the RDS CA bundle, no retryable writes on DocumentDB). |
| `security_group_id` | Cluster security group. |
| `kms_key_arn` | Storage key (ADR-023). Not for secrets. |
| `secrets_kms_key_arn` | Secrets key (ADR-023) of `docdb-master` and `docdb-app` (grant `kms:Decrypt` via Secrets Manager to readers of the app secret). |
| `app_secret_name` | Application credential secret, <env>/<slug>/docdb-app (ExternalSecret remote key). |
| `app_secret_arn` | Application credential secret ARN. |
| `master_secret_arn` | Admin credential, for the DBA bootstrap only. |

## Encryption keys (ADR-023)

Two rotating keys: `<name>-docdb-storage` (cluster storage and snapshots, not tagged `fintechbankx.io/secrets`, so the
External Secrets roles cannot use it) and `<name>-docdb-secrets` (both Secrets Manager secrets, tagged
`fintechbankx.io/secrets=true`). `tests/kms_split.tftest.hcl` (mock providers) pins the split and rejects one key for
both. Before this change the module used one tagged key (`alias/<name>-docdb`); an existing state would replace the
alias and move the secrets to the new key on the next apply.
