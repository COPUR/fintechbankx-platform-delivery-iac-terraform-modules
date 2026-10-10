# elasticache-redis

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Optional Redis (ElastiCache replication group) for a service that needs a
cache. Encrypted at rest (KMS) and in transit (TLS required), Multi-AZ with
automatic failover when there is at least one replica, slow and engine logs
in CloudWatch. Authentication:
- auth_mode "token" (default): a generated AUTH token, stored with the
connection details in Secrets Manager <env>/<slug>/redis for the
aws-secrets-manager ClusterSecretStore. The token is also in (encrypted)
Terraform state.
- auth_mode "rbac": ElastiCache RBAC user groups managed outside the module.

## Usage

```hcl
module "elasticache_redis" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/elasticache-redis?ref=main"
  # inputs below
}
```

Examples: [`examples/elasticache-redis`](../../examples/elasticache-redis/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`
- `hashicorp/random` `>= 3.6`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | dev, staging or prod (secret name <env>/<slug>/redis). |
| `service_slug` | `string` | required | Service slug / Kubernetes service account. |
| `auth_mode` | `string` | `"token"` | token (generated AUTH token in <env>/<slug>/redis) or rbac (user_group_ids). |
| `name` | `string` | `null` | Name prefix. null uses <environment>-<service_slug>; it must fit the 40-character replication group id with the -redis suffix. |
| `engine_version` | `string` | `"7.1"` | Redis engine version. |
| `node_type` | `string` | `"cache.t4g.small"` | Cache node type. |
| `num_node_groups` | `number` | `1` | Shards. 1 = cluster mode disabled layout. |
| `replicas_per_node_group` | `number` | `1` | Replicas per shard. >= 1 enables Multi-AZ automatic failover (use 1+ outside dev). |
| `vpc_id` | `string` | required | VPC id. |
| `subnet_ids` | `list(string)` | required | Private subnets in at least two AZs. |
| `allowed_security_group_ids` | `list(string)` | required | Security groups allowed to connect on 6379. |
| `user_group_ids` | `list(string)` | `[]` | ElastiCache RBAC user group ids when auth_mode = rbac (users managed outside this module). |
| `kms_key_arn` | `string` | `null` | Storage key override (at rest, snapshots); must not carry `fintechbankx.io/secrets`. null creates `<name>-redis-storage`. |
| `secrets_kms_key_arn` | `string` | `null` | Secrets key override (connection secret `<env>/<slug>/redis`), tagged `fintechbankx.io/secrets=true`, different from `kms_key_arn`. null creates `<name>-redis-secrets`. |
| `snapshot_retention_days` | `number` | `7` | Daily snapshot retention (0 disables). |
| `log_retention_days` | `number` | `30` | CloudWatch retention for slow and engine logs. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `primary_endpoint` | Primary endpoint (TLS, port 6379). |
| `reader_endpoint` | Reader endpoint. |
| `configuration_endpoint` | Configuration endpoint (cluster mode only). |
| `security_group_id` | Redis security group. |
| `kms_key_arn` | Storage key (ADR-023): at rest and snapshots. |
| `secrets_kms_key_arn` | Secrets key (ADR-023) of the connection secret. |
| `secret_name` | Connection secret <env>/<slug>/redis (ExternalSecret remote key). |
| `secret_arn` | Connection secret ARN. |

## Encryption keys (ADR-023)

Two rotating keys: `<name>-redis-storage` (at-rest encryption and snapshots, not tagged `fintechbankx.io/secrets`, so
the External Secrets roles cannot use it) and `<name>-redis-secrets` (the connection secret, tagged
`fintechbankx.io/secrets=true`). `tests/kms_split.tftest.hcl` (mock providers) pins the split and rejects one key for
both. Before this change the module used one tagged key for both; changing the at-rest key of an existing replication
group replaces it, so an existing deployment keeps its key through `kms_key_arn`.
