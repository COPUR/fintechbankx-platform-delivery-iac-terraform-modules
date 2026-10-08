# network-vpc

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Three-AZ VPC for a FinTechBankX cell:
public  - load balancers and NAT gateways only
private - EKS nodes/pods, MSK brokers, Aurora, ElastiCache (egress via NAT)
intra   - no route to the internet (data stores that never need egress)
Interface endpoints keep AWS API traffic (ECR, STS, Secrets Manager, SSM,
CloudWatch Logs) off the NAT path; S3 uses a gateway endpoint.

## Usage

```hcl
module "network_vpc" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/network-vpc?ref=main"
  # inputs below
}
```

Examples: [`examples/network-vpc`](../../examples/network-vpc/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix, e.g. fintechbankx-prod-mec1. |
| `cidr_block` | `string` | required | VPC IPv4 CIDR (a /16 is recommended so EKS pods get room). |
| `azs` | `list(string)` | `null` | Availability Zones to use. null picks the first az_count AZs of the region. |
| `az_count` | `number` | `3` | Number of AZs when azs is null. |
| `private_subnet_cidrs` | `list(string)` | `[]` | Optional explicit private subnet CIDRs (one per AZ). |
| `public_subnet_cidrs` | `list(string)` | `[]` | Optional explicit public subnet CIDRs (one per AZ). |
| `intra_subnet_cidrs` | `list(string)` | `[]` | Optional explicit intra (no internet route) subnet CIDRs (one per AZ). |
| `enable_nat_gateway` | `bool` | `true` | Create NAT gateways for private subnet egress. |
| `single_nat_gateway` | `bool` | `false` | One shared NAT gateway (cheaper, not AZ-resilient; dev only). false = one NAT per AZ. |
| `interface_endpoints` | `list(string)` | `["ecr.api", "ecr.dkr", "sts", "secretsmanager", "ssm", "logs"]` | Interface endpoint service suffixes. |
| `eks_cluster_name` | `string` | `null` | Optional EKS cluster name for kubernetes.io/cluster/<name> subnet tags. |
| `enable_flow_logs` | `bool` | `true` | Send VPC flow logs to CloudWatch Logs. |
| `flow_log_retention_days` | `number` | `90` | Flow log retention in days. |
| `flow_log_kms_key_arn` | `string` | `null` | Optional KMS key for the flow log group (key policy must allow CloudWatch Logs). |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC id. |
| `vpc_cidr_block` | VPC CIDR. |
| `azs` | Availability Zones in subnet order. |
| `public_subnet_ids` | Public subnet ids (one per AZ). |
| `private_subnet_ids` | Private subnet ids (one per AZ) for EKS, MSK, Aurora, ElastiCache. |
| `intra_subnet_ids` | Intra subnet ids (no internet route). |
| `private_route_table_ids` | Private route table ids (one per AZ). |
| `nat_public_ips` | NAT gateway Elastic IPs (allow-list these at partners). |
| `vpc_endpoint_security_group_id` | Security group of the interface endpoints. |
| `public_subnet_cidrs` | Public subnet CIDRs. |
| `private_subnet_cidrs` | Private subnet CIDRs (EKS pods/nodes, MSK brokers, Aurora). For egress allow-lists such as Istio ServiceEntry/Sidecar. |
| `intra_subnet_cidrs` | Intra subnet CIDRs. |
