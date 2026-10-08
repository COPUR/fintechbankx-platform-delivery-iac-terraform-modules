# operator-access

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

One in-VPC operator host per environment, reachable through AWS Systems Manager Session Manager only:

- private subnet, no public IP, no key pair, no inbound security group rule (Session Manager connects outbound);
- IMDSv2 required (hop limit 1), encrypted gp3 root volume (`kms_key_arn` or the account EBS default key);
- instance role with `AmazonSSMManagedInstanceCore` only; operators get their database credential through
  [`operator-db-access`](../operator-db-access/README.md) roles, not through the instance role;
- egress only to `egress_cidr_blocks` (normally the VPC CIDR) on 443 (SSM, KMS, Secrets Manager endpoints) and 5432.

A service database admits the host by adding `operator_security_group_id` to the `aurora-postgresql`
`allowed_security_group_ids`. Session logging and the Session Manager preferences document are account settings and
are not managed here.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | `<name_prefix>-<environment>`. |
| `vpc_id` | `string` | required | VPC id. |
| `subnet_id` | `string` | required | Private subnet. |
| `egress_cidr_blocks` | `list(string)` | required | IPv4 prefixes /8 or longer (no `0.0.0.0/0`). |
| `egress_ports` | `list(number)` | `[443, 5432]` | Egress TCP ports. |
| `instance_type` | `string` | `"t3.small"` | x86_64 to match the AMI parameter. |
| `ami_ssm_parameter` | `string` | Amazon Linux 2023 x86_64 | Public SSM parameter with the AMI id (changes are ignored after creation). |
| `kms_key_arn` | `string` | `null` | Root volume key. |
| `root_volume_size_gb` | `number` | `20` | Root volume size. |
| `permissions_boundary_arn` | `string` | `null` | Boundary for the instance role. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|---|---|
| `operator_security_group_id` | Security group of the host. |
| `instance_id` | Target of `aws ssm start-session`. |
| `instance_role_arn` | Instance role. |

## Tests

`tests/host.tftest.hcl` (mock provider, `command = plan`): no public IP, IMDSv2, encrypted root volume, private
subnet, egress 443/5432 inside the VPC CIDR only, SSM core policy; `0.0.0.0/0` rejected.
