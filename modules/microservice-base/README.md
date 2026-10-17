# microservice-base

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Baseline AWS resources every FinTechBankX service gets: a CloudWatch log
group, SSM configuration pointers, a runtime bootstrap secret, a workload
IAM role (ECS task principal or EKS IRSA) and a managed least-privilege
policy that grants read access to exactly those SSM parameters and secret.

## Usage

```hcl
module "microservice_base" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/microservice-base?ref=main"
  # inputs below
}
```

Examples: [`examples/microservice-base-irsa`](../../examples/microservice-base-irsa/main.tf). Consumer contract fixture: [`tests/consumer-compat`](../../tests/consumer-compat/service-deploy-terraform/main.tf).

## Requirements

- Terraform `>= 1.3.0`
- `hashicorp/aws` `>= 5.40, < 6.0`
- `hashicorp/random` `>= 3.6`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `service_name` | `string` | required | Human-readable service name (used in descriptions). |
| `service_slug` | `string` | required | Kebab-case service slug, usually the Kubernetes service account name (e.g. loan-lifecycle-service). |
| `environment` | `string` | required | Deployment environment (dev, staging, prod). |
| `database_engine` | `string` | required | Database engine pointer written to SSM (aurora-postgresql, none, ...). |
| `cache_engine` | `string` | required | Cache engine pointer written to SSM (redis, none, ...). |
| `identity_provider_url` | `string` | required | OIDC issuer URL (Keycloak realm fintechbankx). |
| `observability_endpoint` | `string` | required | OTLP or metrics endpoint written to SSM. |
| `parameter_prefix` | `string` | `"/openfinance"` | Base SSM parameter path prefix. New services use /fintechbankx; the default keeps the historic /openfinance path. |
| `log_group_prefix` | `string` | `null` | CloudWatch log group prefix. null (default) follows parameter_prefix. Set it to pin an existing log group name. |
| `log_retention_days` | `number` | `30` | CloudWatch log retention in days. |
| `log_group_kms_key_arn` | `string` | `null` | Optional KMS key for the log group. The key policy must allow logs.<region>.amazonaws.com. |
| `kms_key_arn` | `string` | `null` | Optional customer-managed KMS key for the runtime secret. null uses the aws/secretsmanager key. |
| `runtime_secret_name` | `string` | `null` | Runtime secret name. null (default) uses the contract name <env>/<slug>/runtime, which the aws-secrets-manager ClusterSecretStore (reads <env>/*) can sync. Set <env>-<slug>/runtime to keep a secret created before 2026-10-08. |
| `secret_recovery_window_in_days` | `number` | `7` | Secrets Manager recovery window for the runtime secret. |
| `workload_principal` | `string` | `"ecs-tasks.amazonaws.com"` | AWS service principal allowed to assume the workload role when IRSA is not used. |
| `eks_oidc_provider_arn` | `string` | `null` | EKS IAM OIDC provider ARN. When set, the workload role trusts the Kubernetes service account (IRSA) instead of workload_principal. |
| `eks_oidc_provider_url` | `string` | `null` | EKS OIDC issuer URL (with or without https://). Required with eks_oidc_provider_arn. |
| `kubernetes_namespace` | `string` | `null` | Namespace of the service account (IRSA). |
| `kubernetes_service_account` | `string` | `null` | Service account name (IRSA). |
| `attach_runtime_access_policy` | `bool` | `true` | Attach the runtime access policy to the workload role created here. |
| `permissions_boundary_arn` | `string` | `null` | Optional IAM permissions boundary for the workload role. |
| `tags` | `map(string)` | `{}` | Additional resource tags. |

## Outputs

| Name | Description |
|---|---|
| `service_info` | Service name, slug and environment. |
| `cloudwatch_log_group_name` | CloudWatch log group name. |
| `cloudwatch_log_group_arn` | CloudWatch log group ARN. |
| `workload_role_arn` | Workload IAM role ARN (ECS task role or IRSA role). |
| `workload_role_name` | Workload IAM role name. |
| `secret_arn` | Runtime bootstrap secret ARN. |
| `secret_name` | Runtime bootstrap secret name (<env>/<slug>/runtime). |
| `runtime_access_policy_arn` | Managed policy granting read of this service's SSM path and runtime secret; attach it to your own IRSA role. |
| `ssm_parameter_root` | SSM path root <parameter_prefix>/<env>/<slug>. |
| `ssm_parameter_paths` | Names of the SSM parameters written by the module. |

## Compatibility notes (2026-10 change)

Every input and output the service repos use (`service_name`, `service_slug`, `environment`, `database_engine`,
`cache_engine`, `identity_provider_url`, `observability_endpoint`, `parameter_prefix`, `log_retention_days`, `tags`;
outputs `secret_arn`, `cloudwatch_log_group_name`) is unchanged. All new inputs are optional.

| Change | Effect on existing callers |
|---|---|
| Log group name follows `parameter_prefix` (`<prefix>/<env>/<slug>`) | Callers on the default prefix keep `/openfinance/<env>/<slug>`. Callers passing `/fintechbankx` get `/fintechbankx/<env>/<slug>` instead of `/openfinance/<env>/<slug>`; set `log_group_prefix = "/openfinance"` to keep an already-created log group. |
| `ignore_changes = [secret_string]` on the runtime secret version | The value is set once and rotated by Secrets Manager. |
| `timestamp()` removed from the runtime secret value (2026-10-08) | The value is now `{"token": ...}` only, so plans are stable without relying on `ignore_changes`. Existing secrets are untouched (`ignore_changes`). |
| `kms_key_arn` | Optional customer-managed key for the runtime secret. |
| IRSA (`eks_oidc_provider_arn`, `eks_oidc_provider_url`, `kubernetes_namespace`, `kubernetes_service_account`) | When set, the workload role trusts `system:serviceaccount:<ns>:<sa>` instead of `ecs-tasks.amazonaws.com`. |
| `runtime_access_policy_arn` output and attachment | A managed policy for reading `<prefix>/<env>/<slug>/*` and the runtime secret; attached to the module's workload role by default and attachable to the service's own IRSA role. |
| Default runtime secret name `<env>/<slug>/runtime` (2026-10-08, **breaking**) | The historic default `<env>-<slug>/runtime` is outside `<env>/*`, which the `aws-secrets-manager` ClusterSecretStore can read. Callers that already applied the old default get a plan that replaces the secret (new name, new value, runtime access policy follows). To keep the existing secret, set `runtime_secret_name = "<env>-<slug>/runtime"`. |

## Tests

`terraform test` (Terraform >= 1.7, mock providers, no credentials) in [`tests/`](tests): default log group and SSM names unchanged; runtime secret under `<env>/` and its override; runtime secret value stable (no `timestamp()`, `command = apply` with an overridden `random_password`); `log_group_prefix` pin; IRSA `sub`; IRSA without namespace fails.
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.
