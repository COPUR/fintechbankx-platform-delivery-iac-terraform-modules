# eks-cluster

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Amazon EKS control plane plus managed node groups spread across the private
subnets of every AZ. Secrets are envelope-encrypted with a customer-managed
KMS key, all control-plane log types go to CloudWatch, the endpoint is
private by default and an IAM OIDC provider is created for IRSA.

## Usage

```hcl
module "eks_cluster" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/eks-cluster?ref=main"
  # inputs below
}
```

Examples: [`examples/eks-cluster`](../../examples/eks-cluster/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`
- `hashicorp/tls` `>= 4.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | required | EKS cluster name, e.g. fintechbankx-prod. |
| `kubernetes_version` | `string` | `"1.31"` | Kubernetes minor version. Check EKS standard support before changing. |
| `subnet_ids` | `list(string)` | required | Private subnets, one per AZ (network-vpc output private_subnet_ids). |
| `endpoint_public_access` | `bool` | `false` | Expose the Kubernetes API publicly (restricted to endpoint_public_access_cidrs). |
| `endpoint_public_access_cidrs` | `list(string)` | `[]` | CIDRs allowed to reach a public API endpoint. |
| `cluster_log_types` | `list(string)` | `["api", "audit", "authenticator", "controllerManager", "scheduler"]` | Control plane log types sent to CloudWatch. |
| `log_retention_days` | `number` | `90` | Control plane log retention in days. |
| `log_group_kms_key_arn` | `string` | `null` | Optional KMS key for the control plane log group (key policy must allow CloudWatch Logs). |
| `kms_key_arn` | `string` | `null` | Existing KMS key for secrets and node volumes. null creates a dedicated key with rotation. |
| `cluster_admin_role_arns` | `list(string)` | `[]` | IAM roles granted AmazonEKSClusterAdminPolicy through EKS access entries (break-glass / platform admins). |
| `node_groups` | `map(...)` | `see variables.tf` | Managed node groups. Each spans all subnet_ids unless subnet_ids is set. |
| `addons` | `map(...)` | `see variables.tf` | EKS add-ons. null version lets EKS pick the default for the Kubernetes version; pin versions for prod. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Cluster name. |
| `cluster_arn` | Cluster ARN. |
| `cluster_endpoint` | Kubernetes API endpoint. |
| `cluster_certificate_authority_data` | Base64 cluster CA. |
| `cluster_security_group_id` | EKS-managed cluster security group, attached to managed nodes. Services pass it as workload_security_group_id. |
| `oidc_provider_arn` | IAM OIDC provider ARN (services: eks_oidc_provider_arn). |
| `oidc_provider_url` | OIDC issuer without https:// (services: eks_oidc_provider_url). |
| `kms_key_arn` | KMS key used for secrets encryption and node volumes. |
| `node_role_arn` | Node IAM role ARN. |
