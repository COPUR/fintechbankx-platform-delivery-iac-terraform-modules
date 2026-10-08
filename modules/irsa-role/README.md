# irsa-role

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

IAM role that exactly one Kubernetes service account can assume through the
EKS OIDC provider (IRSA). Trust: system:serviceaccount:<namespace>:<sa>.

## Usage

```hcl
module "irsa_role" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/irsa-role?ref=main"
  # inputs below
}
```

Examples: [`examples/irsa-role`](../../examples/irsa-role/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `role_name` | `string` | required | IAM role name, e.g. <env>-<service-slug>-irsa. |
| `description` | `string` | `"IRSA role managed by fintechbankx terraform-modules"` | Role description. |
| `oidc_provider_arn` | `string` | required | EKS IAM OIDC provider ARN (eks-cluster output oidc_provider_arn). |
| `oidc_provider_url` | `string` | required | EKS OIDC issuer URL, with or without https:// (eks-cluster output oidc_provider_url). |
| `service_accounts` | `list(...)` | required | Service accounts allowed to assume the role. Normally exactly one. |
| `policy_arns` | `map(string)` | `{}` | Managed policies to attach, keyed by a stable name (e.g. { runtime = module.service_base.runtime_access_policy_arn }). |
| `inline_policy_json` | `string` | `null` | Optional inline policy document. |
| `max_session_duration` | `number` | `3600` | Maximum session duration in seconds. |
| `permissions_boundary_arn` | `string` | `null` | Optional permissions boundary. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | Role ARN for the service account annotation eks.amazonaws.com/role-arn (Helm serviceAccount.roleArn). |
| `role_name` | Role name. |

## Tests

`terraform test` (Terraform >= 1.7, mock AWS provider, `command = plan`, no credentials) in [`tests/`](tests): exact `sub` and `aud`; wildcard service account rejected.
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.
