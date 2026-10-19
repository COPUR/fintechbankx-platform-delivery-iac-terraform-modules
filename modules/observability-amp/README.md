# observability-amp

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Amazon Managed Service for Prometheus workspace (remote-write target for the
in-cluster Prometheus/OTel collector in fintechbankx-platform-observability-sre-operations)
plus an optional Amazon Managed Grafana workspace. A managed policy for
remote write and one for query are exported for IRSA roles.

## Usage

```hcl
module "observability_amp" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/observability-amp?ref=main"
  # inputs below
}
```

Examples: [`examples/observability-amp`](../../examples/observability-amp/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Workspace alias/name, e.g. fintechbankx-prod. |
| `kms_key_arn` | `string` | `null` | Optional customer-managed KMS key for the AMP workspace. null uses an AWS-owned key. Changing it replaces the workspace. |
| `log_retention_days` | `number` | `30` | Retention for AMP workspace logs. |
| `alertmanager_definition` | `string` | `null` | Optional Alertmanager YAML (alertmanager_config: ...). |
| `rule_group_namespaces` | `map(string)` | `{}` | Prometheus rule files (YAML) keyed by namespace name, e.g. from the observability repo. |
| `enable_grafana` | `bool` | `false` | Create an Amazon Managed Grafana workspace (check regional availability first). |
| `grafana_authentication_providers` | `list(string)` | `["AWS_SSO"]` | Grafana authentication providers (AWS_SSO or SAML). |
| `grafana_version` | `string` | `"10.4"` | Managed Grafana version. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `workspace_id` | AMP workspace id. |
| `workspace_arn` | AMP workspace ARN. |
| `prometheus_endpoint` | AMP workspace endpoint (query base URL). |
| `remote_write_url` | Remote write URL for Prometheus/OTel collector (SigV4, service aps). |
| `remote_write_policy_arn` | Attach to the collector's IRSA role. |
| `query_policy_arn` | Attach to roles that query metrics (Grafana, KEDA, alert tooling). |
| `grafana_endpoint` | Managed Grafana URL (null when disabled). |
