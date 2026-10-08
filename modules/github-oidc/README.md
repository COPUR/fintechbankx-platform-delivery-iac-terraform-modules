# github-oidc

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

GitHub Actions OIDC federation for one AWS account / environment, matching
fintechbankx-platform-delivery-iac-cicd-templates
(docs/delivery/CONSUMING_DELIVERY_WORKFLOWS.md section 4). Per service:
- ecr-push  : sub repo:<org>/<repo>:ref:refs/heads/main; push/pull on
fintechbankx/<image_name> only
- deploy    : sub repo:<org>/<repo>:environment:<env>; eks:DescribeCluster
plus an EKS access entry in Kubernetes group
fintechbankx:deploy:<namespace> (bind that group to a
namespaced Role with a RoleBinding; never cluster-admin)
- tf-plan   : sub pull_request or ref:refs/heads/main; ReadOnlyAccess plus
state read and lock on the service's own state key
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
| `services` | `map(...)` | `{}` | Service id -> GitHub repository, image name (= Kubernetes service account), context namespace and Terraform state key. |
| `create_ecr_push_roles` | `bool` | `true` | Create ECR push roles in this account (the account that holds the ECR repositories). |
| `eks_cluster_name` | `string` | required | EKS cluster the deploy roles target. |
| `create_eks_access_entries` | `bool` | `true` | Create EKS access entries mapping deploy roles to fintechbankx:deploy:<namespace>. |
| `terraform_state_bucket` | `string` | required | S3 state bucket of this environment. |
| `terraform_lock_table` | `string` | `"fintechbankx-terraform-locks"` | DynamoDB lock table. |
| `terraform_state_kms_key_arn` | `string` | `null` | KMS key of the state bucket (null for SSE-S3). |
| `apply_policy_arns` | `list(string)` | `[]` | Policies granting what service Terraform creates (Aurora, KMS, Secrets Manager, IAM under a boundary). Kept explicit on purpose. |
| `permissions_boundary_arn` | `string` | `null` | Permissions boundary for every CI role (recommended for tf-apply). |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `oidc_provider_arn` | GitHub OIDC provider ARN. |
| `role_arns` | Service id -> { ecr-push, deploy, tf-plan, tf-apply } role ARNs (repository variables ECR_PUSH_ROLE_ARN, EKS_DEPLOY_ROLE_ARN_<ENV>, ...). |
| `deploy_kubernetes_groups` | Service id -> Kubernetes group to bind to a namespaced Role (RoleBinding lives with the mesh/k8s platform repo). |

## Kubernetes side (not in this module)

Deploy roles enter the cluster as Kubernetes group `fintechbankx:deploy:<namespace>` through an EKS access entry
without any access policy, so they can do nothing until a `RoleBinding` in that namespace binds the group to a
namespaced `Role` (Helm release verbs on Deployments, Services, ConfigMaps, ExternalSecrets, HPAs, PDBs, ...). That
Role and RoleBinding belong to the mesh/Kubernetes platform repository. Never bind the group to `cluster-admin`.

The `tf-apply` roles get only state access by default; pass `apply_policy_arns` (and preferably
`permissions_boundary_arn`) for what service Terraform creates.

Role names: `gha-<env>-<service id without svc->-<kind>`, at most 59 characters (service ids are limited to 42).

## Tests

`terraform test` (Terraform >= 1.7, mock AWS provider, `command = plan`, no credentials) in [`tests/`](tests): role names within 64 characters; `sub` per role kind (main, environment, pull request); no wildcard trust; over-long service id rejected.
Run `terraform init -backend=false && terraform test` in this directory; CI runs it through
`scripts/ci/terraform-validate-all.sh`.
