# ecr-repository

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Private ECR repository: immutable tags, scan on push, KMS encryption and a
lifecycle policy that keeps the newest release images and expires untagged
layers.

## Usage

```hcl
module "ecr_repository" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/ecr-repository?ref=main"
  # inputs below
}
```

Examples: [`examples/ecr-repository`](../../examples/ecr-repository/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Repository name, e.g. fintechbankx/loan-lifecycle-service. |
| `kms_key_arn` | `string` | `null` | Customer-managed KMS key ARN. null uses the AWS-managed aws/ecr key (still KMS). |
| `max_tagged_images` | `number` | `50` | Number of images to retain. |
| `untagged_expiry_days` | `number` | `7` | Days after which untagged images expire. |
| `pull_principal_arns` | `list(string)` | `[]` | Extra principals (e.g. other workload accounts) allowed to pull. Same-account IAM access needs no entry. |
| `force_delete` | `bool` | `false` | Allow deleting the repository while it still holds images (keep false outside sandboxes). |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `repository_url` | Helm value image.repository. |
| `repository_arn` | Repository ARN (scope CI push permissions to it). |
| `repository_name` | Repository name. |
