# external-secrets-irsa

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

IRSA roles for External Secrets Operator (contract addendum 2026-10-08, security review 2026-10-08). Two read-only
roles, one per ClusterSecretStore:

| Role | Service account (namespace `external-secrets`) | ClusterSecretStore | Reads |
|---|---|---|---|
| `<cluster>-external-secrets` (output `role_arn`) | `external-secrets` | `aws-secrets-manager` | `<env>/*`, with an explicit Deny on `<env>/platform/*`, `<env>/identity-keycloak/*`, `<env>/identity-openldap/*` |
| `<cluster>-external-secrets-platform` (output `platform_secrets_role_arn`) | `external-secrets-platform` (token only) | `aws-secrets-manager-platform` | `<env>/platform/*`, `<env>/identity-keycloak/*`, `<env>/identity-openldap/*`, `<env>/*/oidc-client-??????` (realm import) |

Both allow only `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret`, plus `kms:Decrypt` through
Secrets Manager (`kms:ViaService`) with keys tagged `fintechbankx.io/secrets=true`. No Put/Create. The prefixes are
`platform_secret_prefixes` (default matches the identity repo's `deploy/terraform`: `identity-keycloak/*` and
`identity-openldap/admin`).

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
| `create_platform_role` | `bool` | `true` | Create the platform-store role (ClusterSecretStore aws-secrets-manager-platform). |
| `platform_service_account` | `string` | `"external-secrets-platform"` | Token-only service account the platform ClusterSecretStore authenticates as. |
| `platform_role_name` | `string` | `null` | Platform-store role name override. null uses <cluster_name>-external-secrets-platform. |
| `platform_secret_prefixes` | `list(string)` | `["platform", "identity-keycloak", "identity-openldap"]` | Secret prefixes under <env>/ that only the platform store may read (denied to the service store). |
| `kms_key_tag_key` | `string` | `"fintechbankx.io/secrets"` | Tag key that marks KMS keys the operator may decrypt with. |
| `kms_key_tag_value` | `string` | `"true"` | Tag value that marks KMS keys the operator may decrypt with. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | Service store role: annotate SA external-secrets/external-secrets with this ARN (eks.amazonaws.com/role-arn). |
| `role_name` | Role name. |
| `secret_arn_pattern` | Secrets the operator can read. |
| `platform_secrets_role_arn` | Platform store role: annotate SA external-secrets/external-secrets-platform (mesh overlay parameter PLATFORM_SECRETS_ROLE_ARN). null when create_platform_role is false. |
| `platform_secret_arn_patterns` | Secrets the platform store can read (and the service store cannot, except oidc-client). |

## Compatibility notes (2026-10-08)

- The service-store role keeps its module address, name and output; it loses `secretsmanager:ListSecretVersionIds`
  (ESO does not use it) and can no longer read `<env>/platform/*`, `<env>/identity-keycloak/*` or
  `<env>/identity-openldap/*`. Anything that synced those through `aws-secrets-manager` must move to
  `aws-secrets-manager-platform`.
- A second role is created by default (`create_platform_role = false` to skip).

## Tests

`terraform test` (mock providers, no credentials) in [`tests/`](tests): trusted service accounts per store; service
store reads `<env>/*` with explicit Deny on the platform prefixes; platform store reads only its prefixes and
`oidc-client`; only GetSecretValue/DescribeSecret/kms:Decrypt; KMS via Secrets Manager on tagged keys.
