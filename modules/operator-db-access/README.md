# operator-db-access

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

One IAM role per service slug, `<env>-<slug>-db-import`, for operators who load data into a service database from the
[`operator-access`](../operator-access/README.md) host:

- `secretsmanager:GetSecretValue` only on `<env>/<slug>/db-import` (ARN with the 6-character random suffix);
- `kms:Decrypt` only with `kms:ViaService = secretsmanager.<region>.amazonaws.com` and
  `kms:EncryptionContext:SecretARN` equal to that secret, on the service CMK when `kms_key_arns` names it;
- assumable only by `trusted_principal_arns` (IAM Identity Center permission-set roles; this module creates no
  permission set, user or group). Wildcards are rejected.

The `db-import` secret itself is created and filled by the owning squad's DBA process (not by this module or by
`aurora-postgresql`); it should hold a role with only the grants the import needs.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | `dev`, `staging` or `prod`. |
| `service_slugs` | `list(string)` | required | Service slugs, one role each. |
| `trusted_principal_arns` | `list(string)` | required | Role ARNs allowed to assume the roles. |
| `kms_key_arns` | `map(string)` | `{}` | CMK per slug. |
| `max_session_duration_seconds` | `number` | `3600` | 900..14400. |
| `permissions_boundary_arn` | `string` | `null` | Boundary. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|---|---|
| `role_arns` | Role ARN per slug. |
| `db_import_secret_names` | `<env>/<slug>/db-import` per slug. |

## Tests

`tests/roles.tftest.hcl` (mock provider): one role per slug, trust limited to the listed ARNs, secret read and KMS
decrypt conditions exactly as above; wildcard principals and malformed slugs rejected.
