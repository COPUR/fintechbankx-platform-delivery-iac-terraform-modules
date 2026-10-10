# stacks/platform

Status: **Proposed**. Validated with `terraform validate` and a type-check of the tfvars examples; never planned
against an AWS account or applied.

Composition root for one environment (one cell in one region, default `me-central-1`):

| Module | What it creates |
|---|---|
| [`network-vpc`](../../modules/network-vpc/README.md) | 3-AZ VPC, public/private/intra subnets, NAT per AZ (one shared NAT in dev), VPC endpoints, flow logs |
| [`eks-cluster`](../../modules/eks-cluster/README.md) | EKS, managed node groups across the private subnets, KMS secrets encryption, OIDC provider, core add-ons |
| [`msk-cluster`](../../modules/msk-cluster/README.md) | Amazon MSK, 3 brokers / 3 AZs, TLS, IAM auth, KMS, explicit topics, topic-admin policy |
| [`observability-amp`](../../modules/observability-amp/README.md) | Amazon Managed Prometheus (+ optional Managed Grafana) |
| [`ecr-repository`](../../modules/ecr-repository/README.md) | `fintechbankx/<image_name>` per service, immutable tags, scan on push |
| [`external-secrets-irsa`](../../modules/external-secrets-irsa/README.md) | IRSA role for ClusterSecretStore `aws-secrets-manager` (reads `<env>/*`) |
| [`irsa-role`](../../modules/irsa-role/README.md) | `<cluster>-obs-{prometheus,otel-gateway,tempo,loki,yace}` roles ([observability.tf](observability.tf)) |
| [`aurora-postgresql`](../../modules/aurora-postgresql/README.md) | Small Grafana database (staging, prod), credential container `<env>/observability/grafana-db` |
| [`github-oidc`](../../modules/github-oidc/README.md) | GitHub Actions OIDC provider and per-service ecr-push / deploy / tf-plan / tf-apply roles |
| [`operator-access`](../../modules/operator-access/README.md), [`operator-db-access`](../../modules/operator-db-access/README.md) | Off by default (`operator_access_enabled`): SSM-only operator host in a private subnet with KMS-encrypted session logs, the `ssmmessages`/`ec2messages`/`kms` interface endpoints, and per-service roles `<env>-<slug>-db-import` for `operator_db_import_service_slugs`, assumable by `operator_principal_arns` with a source identity; `db-import` secrets on each service's secrets key `operator_db_import_kms_key_arns` ([operator.tf](operator.tf), section "Operator database access") |

[observability.tf](observability.tf) also creates SSE-KMS buckets `fintechbankx-<env>-obs-{traces,logs-chunks,logs-ruler}` (TLS-only, public access blocked). MSK enhanced monitoring defaults to `PER_BROKER`; Aurora and MSK are tagged `fintechbankx.io/observability=enabled` for YACE.

Per-service databases (Aurora, DocumentDB, Redis) are **not** here: each service owns them in its own
`deploy/terraform` (database per service).

## Use

```bash
cp environments/dev.tfvars.example environments/dev.tfvars
cp environments/dev.backend.hcl.example environments/dev.backend.hcl
terraform init -backend-config=environments/dev.backend.hcl
terraform plan -var-file=environments/dev.tfvars
```

The state bucket and lock table (`fintechbankx-terraform-state-<env>`, `fintechbankx-terraform-locks`) must exist
first; they are bootstrapped outside this stack. The bootstrap must merge the output
`terraform_state_bucket_policy_json` into the state bucket policy so a CI Terraform role can read only its own
state key (see [`modules/github-oidc`](../../modules/github-oidc/README.md)).

The stack enforces this: `verify_terraform_state_bucket_policy` (default `true`) reads the bucket policy at plan time
and fails the plan unless the four `DenyCiTerraformRoles*` statements are in it as `Deny`
(`DenyCiTerraformRolesOtherStateObjects` among them). The identity running the plan needs `s3:GetBucketPolicy` on
the bucket. First run of a new environment: plan once with `-var verify_terraform_state_bucket_policy=false`, merge
`terraform_state_bucket_policy_json` (shown in the plan's outputs) in the bootstrap, then plan normally. To let this
stack own the policy instead, set `manage_terraform_state_bucket_policy = true` and pass the bootstrap's existing
statements in `terraform_state_bucket_policy_source_json` (the attachment replaces the whole bucket policy).
The verification checks statement `Sid`s and `Effect = Deny` only, not their principals, actions or conditions: it is
a tripwire against a bootstrap that forgot the merge, not a proof that the merged statements are correct (review the
bucket policy itself for that).

## Outputs consumed elsewhere

| Output | Consumer |
|---|---|
| `vpc_id`, `private_subnet_ids`, `workload_security_group_id`, `eks_oidc_provider_arn`, `eks_oidc_provider_url` | service repos' `deploy/terraform` inputs of the same names |
| `msk_cluster_arn`, `msk_bootstrap_brokers_sasl_iam` | `msk-client-access` in service repos; `KAFKA_BOOTSTRAP_SERVERS` |
| `msk_topic_admin_policy_arn` | topic provisioning job (event-streaming repo) |
| `ecr_repository_urls`, `github_oidc_role_arns` | service repos' GitHub variables (`ECR_PUSH_ROLE_ARN`, `EKS_DEPLOY_ROLE_ARN_<ENV>`) |
| `deploy_kubernetes_groups` | mesh repo: RoleBinding per namespace |
| `terraform_state_bucket_policy_json` | state bucket bootstrap (per environment) |
| `external_secrets_role_arn` | mesh repo: `external-secrets` service account annotation (ClusterSecretStore `aws-secrets-manager`) |
| `platform_secrets_role_arn` | mesh repo: `external-secrets-platform` service account annotation, overlay parameter `PLATFORM_SECRETS_ROLE_ARN` (ClusterSecretStore `aws-secrets-manager-platform`) |
| `vpc_cidr`, `private_subnet_cidrs`, `msk_security_group_id`, `msk_subnet_ids` | mesh repo `params.env` |
| `ingress_tls_secret_name` | mesh repo: gateway certificate at Secrets Manager `<env>/platform/ingress-tls` (created and filled outside Terraform; no certificate material in this repository) |
| `operator_security_group_id`, `operator_instance_id`, `operator_db_import_role_arns`, `operator_session_log_group_name`, `operator_session_log_kms_key_arn` | service repos: add the security group to the database `allowed_security_group_ids`; operators: credential path in "Operator database access"; Identity Center permission sets: `kms:GenerateDataKey` on the session-log key; account baseline: Session Manager preferences when `manage_session_manager_preferences` is `false` |
| `amp_remote_write_url`, `observability_role_arns`, `observability_buckets`, `grafana_db_secret_name` | observability repo (IRSA for `observability/{prometheus,otel-gateway,tempo,loki,yace}`) |

## Operator database access

Off by default. With `operator_access_enabled = true` the stack adds the interface endpoints Session Manager needs on a
host without internet (`ssm`, `ssmmessages`, `ec2messages`) plus `kms`, `secretsmanager`, `sts` and `logs`
(`vpc_interface_endpoints` keeps the defaults), creates the operator host with session logging
([`operator-access`](../../modules/operator-access/README.md)) and, for `operator_db_import_service_slugs`, the
`<env>-<slug>-db-import` roles and empty secrets ([`operator-db-access`](../../modules/operator-db-access/README.md)).
`operator_db_import_kms_key_arns` must name each service's ADR-023 secrets key (its `aurora-postgresql` output
`secrets_kms_key_arn`); the plan fails without it. `tests/operator.tftest.hcl` (mock providers) checks the endpoints,
the key wiring and the `operator_session_log_kms_key_arn` output.

Credential path (the password never lands on the operator host):

1. On the workstation, with the Identity Center permission-set session:
   `aws sts assume-role --role-arn <operator_db_import_role_arns[slug]> --role-session-name <user>
   --source-identity <user>`. The trust policy refuses the call without a source identity.
2. With those credentials, read `<env>/<slug>/db-import` (`aws secretsmanager get-secret-value`) straight into the
   environment of the `psql` (or `pg_restore`) process, for example `PGPASSWORD`; do not write it to a file.
3. Open a port-forwarding session through the host, with the permission-set credentials (not the db-import role).
   The permission set needs `ssm:StartSession` on the host and on the document
   `AWS-StartPortForwardingSessionToRemoteHost`, and `kms:GenerateDataKey` on the session-log key
   (`operator_session_log_kms_key_arn`): once the Session Manager preferences document sets that key as `kmsKeyId`
   (prerequisite under "Evidence trail"), session data is encrypted with it and the caller who starts the session
   needs a data key from it:
   `aws ssm start-session --target <operator_instance_id> --document-name AWS-StartPortForwardingSessionToRemoteHost
   --parameters host=<writer endpoint>,portNumber=5432,localPortNumber=15432`.
4. Connect from the workstation with certificate checks against the real endpoint name:
   `psql "host=<writer endpoint> hostaddr=127.0.0.1 port=15432 dbname=<db> user=<import role> sslmode=verify-full
   sslrootcert=<RDS CA bundle>"`. TLS runs end to end between the workstation and Aurora; the host only relays the
   encrypted TCP stream and never sees the password or the data.

Evidence trail:

- CloudTrail `AssumeRole` (the db-import role) and `GetSecretValue` (`<env>/<slug>/db-import`) carry the source
  identity, because both use the session created with `--source-identity <user>` in step 1.
- CloudTrail `StartSession` (step 3) is made with the Identity Center permission-set credentials, so it carries no
  db-import source identity. It is attributed through the permission-set role session name, which is the Identity
  Center user name (`userIdentity.arn` ends in `.../AWSReservedSSO_<permission set>_<id>/<user>`).
- Port-forwarding sessions (the database path) have no transcript, because the stream is TLS-encrypted PostgreSQL.
  Shell sessions on the host reach the KMS-encrypted log group `operator_session_log_group_name` only when the
  account/region Session Manager preferences document `SSM-SessionManagerRunShell` points at that group and key.
  That document is a prerequisite: with `manage_session_manager_preferences = true` this stack creates it; with
  `false` (the default) the owner of the account baseline, who manages the account's Session Manager preferences
  outside this repository, sets `cloudWatchLogGroupName`, `cloudWatchEncryptionEnabled = true` and `kmsKeyId` to
  this stack's outputs. Without the document, sessions are not logged and session data is not encrypted with the
  key.
- The database's pgaudit lines land in its `postgresql` log group (`operator-db-access` can grant the db-import role
  read access to it through `postgresql_log_group_arns`; not wired in this stack yet).

Check before the first operator session in an environment (and after any change to the preferences):

```
aws ssm get-document --name SSM-SessionManagerRunShell --query Content --output text
```

Expected: `inputs.cloudWatchLogGroupName` = `operator_session_log_group_name`, `inputs.cloudWatchEncryptionEnabled`
= `true` and `inputs.kmsKeyId` = `operator_session_log_kms_key_arn`. `InvalidDocument` means the document does not
exist and sessions are not logged: ask the account-baseline owner to create it, or set
`manage_session_manager_preferences = true`. Then start a session as an operator and check that the
`StartSession` event names the user in `userIdentity.arn`.

Cluster-side, the External Secrets roles deny every `<env>/*/db-import` secret; a mesh admission rule rejecting
ExternalSecrets with a remote key ending in `/db-import` is a mesh-repository follow-up.

## Image names

`github_services` in the tfvars examples lists all 15 services. Image name = Kubernetes service account = ECR
repository `fintechbankx/<image_name>`; the names were confirmed by the owning service threads on 2026-10-08
(open finance services use `<capability>-service` in namespace `open-finance`, without an `openfinance-` prefix).
CI role names are `gha-<env>-<service-id without svc->-<kind>` (at most 59 characters; enforced by a variable
validation and a `terraform test` in `modules/github-oidc/tests`).
