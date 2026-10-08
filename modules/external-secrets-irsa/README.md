# external-secrets-irsa

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

IRSA role for External Secrets Operator (contract addendum 2026-10-08):
service account external-secrets/external-secrets backs the single
ClusterSecretStore "aws-secrets-manager". It may read only secrets named
<env>/* in this account and region, and decrypt only through Secrets
Manager with KMS keys tagged fintechbankx.io/secrets=true.

## Usage

```hcl
module "external_secrets_irsa" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/external-secrets-irsa?ref=main"
  # inputs below
}
```

Examples: [`examples/external-secrets-irsa`](../../examples/external-secrets-irsa/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | required | EKS cluster name, used for the default role name. |
| `environment` | `string` | required | Environment; the role reads secrets named <environment>/*. |
| `oidc_provider_arn` | `string` | required | EKS IAM OIDC provider ARN. |
| `oidc_provider_url` | `string` | required | EKS OIDC issuer URL (with or without https://). |
| `namespace` | `string` | `"external-secrets"` | Namespace of External Secrets Operator. |
| `service_account` | `string` | `"external-secrets"` | Service account of External Secrets Operator. |
| `role_name` | `string` | `null` | Role name override. null uses <cluster_name>-external-secrets. |
| `kms_key_tag_key` | `string` | `"fintechbankx.io/secrets"` | Tag key that marks KMS keys the operator may decrypt with. |
| `kms_key_tag_value` | `string` | `"true"` | Tag value that marks KMS keys the operator may decrypt with. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | Annotate the external-secrets service account with this ARN (eks.amazonaws.com/role-arn). |
| `role_name` | Role name. |
| `secret_arn_pattern` | Secrets the operator can read. |
