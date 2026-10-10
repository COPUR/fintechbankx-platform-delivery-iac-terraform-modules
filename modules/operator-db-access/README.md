# operator-db-access

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

One IAM role per service slug, `<env>-<slug>-db-import`, for operators who load data into a service database from the
[`operator-access`](../operator-access/README.md) host:

- `secretsmanager:GetSecretValue` only on `<env>/<slug>/db-import` (ARN with the 6-character random suffix);
- `kms:Decrypt` only with `kms:ViaService = secretsmanager.<region>.amazonaws.com` and
  `kms:EncryptionContext:SecretARN` equal to that secret, on the service CMK when `kms_key_arns` names it;
- assumable only by `trusted_principal_arns` (IAM Identity Center permission-set roles; this module creates no
  permission set, user or group). Wildcards are rejected;
- every session must carry a source identity: the trust statement allows `sts:AssumeRole` and
  `sts:SetSourceIdentity` only with `StringLike sts:SourceIdentity "*"`, so `aws sts assume-role` without
  `--source-identity <your Identity Center user name>` is refused. CloudTrail records the source identity on the
  `AssumeRole` event and on every call made with the session, including `GetSecretValue`.

The `db-import` secret value is written by the owning squad's DBA process (not by Terraform or `aurora-postgresql`); it
should hold a role with only the grants the import needs.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | `dev`, `staging` or `prod`. |
| `service_slugs` | `list(string)` | required | Service slugs, one role each. |
| `trusted_principal_arns` | `list(string)` | required | Role ARNs allowed to assume the roles. |
| `kms_key_arns` | `map(string)` | `{}` | ADR-023 secrets key ARN per slug (`aurora-postgresql` output `secrets_kms_key_arn`); required for every slug while `create_db_import_secrets` is true; key ARNs only (no alias, no wildcard). |
| `max_session_duration_seconds` | `number` | `3600` | 900..14400. |
| `permissions_boundary_arn` | `string` | `null` | Boundary. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|---|---|
| `role_arns` | Role ARN per slug. |
| `db_import_secret_names` | `<env>/<slug>/db-import` per slug. |
| `db_import_secret_arns` | ARN of each created container. |
| `kms_key_arns` | Secrets key per slug used for the container and the `kms:Decrypt` grant. |

## Tests

`tests/roles.tftest.hcl` (mock provider): one role per slug, trust limited to the listed ARNs, secret read and KMS
decrypt conditions exactly as above; wildcard principals and malformed slugs rejected; source identity required; a
missing secrets key for a slug fails the plan (precondition on the container), alias or wildcard key ARNs rejected.

## Secret containers

By default (`create_db_import_secrets = true`) the module also creates the empty
secret `<env>/<slug>/db-import` per service, encrypted with the service's
ADR-023 secrets key from `kms_key_arns`: the secrets-only key tagged
`fintechbankx.io/secrets=true` (`aurora-postgresql` output `secrets_kms_key_arn`),
never the database storage key. The key is required for every slug: without it
the secret would fall back to the AWS managed key `aws/secretsmanager`, which
any principal allowed `GetSecretValue` can use, and `kms:Decrypt` could not be
scoped to a key. Terraform never writes a value: the DBA sets it with
`aws secretsmanager put-secret-value` from a workstation, so the value is not in
state (`fintechbankx.io/value-in-state=false`) and never on the operator host.

Because the secret sits under `<env>/*` and its key is tagged, the External
Secrets service store could otherwise read and decrypt it. Both store roles
therefore carry an explicit Deny of `secretsmanager:*` on
`<env>/*/db-import-??????` ([`external-secrets-irsa`](../external-secrets-irsa/README.md),
`DenyOperatorDbImportSecrets`); the missing tag on the secret itself is not a
control. Output: `db_import_secret_arns`. Rotate the import password after
each production import.
