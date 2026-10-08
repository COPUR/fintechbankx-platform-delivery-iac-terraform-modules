# github-oidc

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

GitHub Actions OIDC federation for one AWS account / environment, matching
fintechbankx-platform-delivery-iac-cicd-templates
(docs/delivery/CONSUMING_DELIVERY_WORKFLOWS.md section 4). Per service:
- ecr-push  : sub repo:<org>/<repo>:ref:refs/heads/main; push/pull on
fintechbankx/<image_name> only
- deploy    : sub repo:<org>/<repo>:environment:<env>; eks:DescribeCluster,
ecr:GetAuthorizationToken and pull (BatchGetImage, GetDownloadUrlForLayer) of
fintechbankx/<image_name> only, for the cosign verify step
plus an EKS access entry in Kubernetes group
fintechbankx:deploy:<namespace> (bind that group to a
namespaced Role with a RoleBinding; never cluster-admin)
- tf-plan   : sub pull_request or ref:refs/heads/main; read-only metadata on
the service's own resources (no AWS-managed policy), state read and lock on
the service's own state key only
- tf-apply  : sub environment:<env> only; state read/write on the
service's key plus caller-provided policies
No long-lived access keys are created.

## Usage

```hcl
module "github_oidc" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/github-oidc?ref=main"
  # inputs below
}
```

Examples: [`examples/github-oidc`](../../examples/github-oidc/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | Environment of this account (GitHub environment name, sub ...:environment:<env>). |
| `github_org` | `string` | `"COPUR"` | GitHub organisation or owner. |
| `create_oidc_provider` | `bool` | `true` | Create the token.actions.githubusercontent.com provider (once per account). |
| `oidc_provider_arn` | `string` | `null` | Existing GitHub OIDC provider ARN when create_oidc_provider is false. |
| `oidc_thumbprints` | `list(string)` | `["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]` | Thumbprints for the GitHub OIDC provider. AWS validates GitHub tokens against its own trust store; the values are still required by the API. |
| `services` | `map(...)` | `{}` | Service id -> GitHub repository, image name (= Kubernetes service account and service slug), context namespace, Terraform state key (unique per service; IAM tag value characters) and optional `resource_name_prefix` (default `<env>-<image_name>`). |
| `create_ecr_push_roles` | `bool` | `true` | Create ECR push roles in this account (the account that holds the ECR repositories). |
| `ecr_registry_account_id` | `string` | `null` | Account holding the fintechbankx/* ECR repositories the deploy roles pull from (cosign verify). null = this account. A cross-account registry also needs a repository policy allowing these roles. |
| `eks_cluster_name` | `string` | required | EKS cluster the deploy roles target. |
| `create_eks_access_entries` | `bool` | `true` | Create EKS access entries mapping deploy roles to fintechbankx:deploy:<namespace>. |
| `terraform_state_bucket` | `string` | required | S3 state bucket of this environment. |
| `terraform_lock_table` | `string` | `"fintechbankx-terraform-locks"` | DynamoDB lock table. |
| `terraform_state_kms_key_arn` | `string` | `null` | KMS key of the state bucket (null for SSE-S3). |
| `apply_policy_arns` | `list(string)` | `[]` | Policies granting what service Terraform creates (Aurora, KMS, Secrets Manager, IAM under a boundary). Kept explicit on purpose; AWS-managed AdministratorAccess, PowerUserAccess, ReadOnlyAccess and ViewOnlyAccess are rejected. |
| `terraform_state_bucket_key_enabled` | `bool` | `false` | Set true if the state bucket uses S3 Bucket Keys (KMS encryption context is then the bucket ARN). |
| `manage_terraform_state_bucket_policy` | `bool` | `false` | Attach `terraform_state_bucket_policy_json` to the state bucket (replaces its whole policy). |
| `terraform_state_bucket_policy_source_json` | `string` | `null` | Existing state-bucket statements to keep, merged before the CI deny statements. |
| `permissions_boundary_arn` | `string` | `null` | Permissions boundary for every CI role (recommended for tf-apply). |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `oidc_provider_arn` | GitHub OIDC provider ARN. |
| `role_arns` | Service id -> { ecr-push, deploy, tf-plan, tf-apply } role ARNs (repository variables ECR_PUSH_ROLE_ARN, EKS_DEPLOY_ROLE_ARN_<ENV>, ...). |
| `deploy_kubernetes_groups` | Service id -> Kubernetes group to bind to a namespaced Role (RoleBinding lives with the mesh/k8s platform repo). |
| `terraform_state_bucket_policy_json` | State-bucket policy denying each CI Terraform role every key but its own. |

## Kubernetes side (not in this module)

Deploy roles enter the cluster as Kubernetes group `fintechbankx:deploy:<namespace>` through an EKS access entry
without any access policy, so they can do nothing until a `RoleBinding` in that namespace binds the group to a
namespaced `Role` (Helm release verbs on Deployments, Services, ConfigMaps, ExternalSecrets, HPAs, PDBs, ...). That
Role and RoleBinding belong to the mesh/Kubernetes platform repository. Never bind the group to `cluster-admin`.

The `tf-apply` roles get only state access by default; pass `apply_policy_arns` (and preferably
`permissions_boundary_arn`) for what service Terraform creates.

## Pull-request plans and state isolation (2026-10-08)

The `tf-plan` role trusts pull requests, so anyone who can open a PR on the service repository can use it. It
therefore has no AWS-managed policy (`ReadOnlyAccess` used to grant `s3:Get*` on every bucket, which overrode the
per-key state scoping, and log reads). It gets:

| Policy | Grants |
|---|---|
| `terraform-state` | `s3:GetObject` on exactly its state key; `s3:ListBucket` with `StringEquals s3:prefix = <key>`; DynamoDB `GetItem` on the lock and digest items and `PutItem`/`DeleteItem` on its own lock item only (exact `dynamodb:LeadingKeys`); `kms:Decrypt` only via S3 and only with encryption context `aws:s3:arn = <bucket>/<key>` |
| `plan-read-own-resources` | Describe/Get/List on the service's own Aurora/DocumentDB, ElastiCache, KMS keys (by alias `alias/<prefix>-*`), Secrets Manager `<env>/<image_name>/*` and `<prefix>/*`, IAM roles/policies `<prefix>-*`, log group tags, SSM `/*/<env>/<image_name>/*`, alarm tags; a `*` statement with only Describe/List calls AWS cannot scope (security groups, subnets, VPCs, engine versions, alias list, alarm and log group lists) |

`<prefix>` is `<env>-<image_name>` (the name the module library gives a service's resources) unless
`resource_name_prefix` is set. `GetSecretValue` on the service's own secrets is needed to refresh
`aws_secretsmanager_secret_version`; those values are in its own state already. A service whose stack manages
other resource types gets `AccessDenied` on plan: extend this policy here (scoped), never attach a broad policy.

Every `tf-plan` / `tf-apply` role carries the tag `TerraformStateKey = <its key>`. The state-bucket policy
(`terraform_state_bucket_policy_json`) denies roles matching `gha-<env>-*-tf-plan|tf-apply` every object except
`${aws:PrincipalTag/TerraformStateKey}` (and `.tflock`), every bucket action except listing their own key, and
everything if the tag is missing. It has a fixed size whatever the number of services. Attach it with
`manage_terraform_state_bucket_policy = true` (pass the bucket's existing statements in
`terraform_state_bucket_policy_source_json`), or merge it into the policy of the bootstrap that owns the bucket.
State keys must be unique per service (validated).

Role names: `gha-<env>-<service id without svc->-<kind>`, at most 59 characters (service ids are limited to 42).

## Tests

`terraform test` (Terraform >= 1.7, mock AWS provider, `command = plan`, no credentials) in [`tests/`](tests): role names within 64 characters; `sub` per role kind (main, environment, pull request); no wildcard trust; over-long service id rejected; no AWS-managed broad policy on any role and none at all on plan roles; plan-role S3 statements reference only its own key, ListBucket limited by exact prefix, no write actions except its own lock item, KMS decrypt via S3 for its own object only, no other service's resources or secrets, `*` only for Describe/List; state-bucket deny statements; duplicate state keys and AdministratorAccess in `apply_policy_arns` rejected; deploy role pulls only its own repository (optionally in `ecr_registry_account_id`) and cannot push.
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.
