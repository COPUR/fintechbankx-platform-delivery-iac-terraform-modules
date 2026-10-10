# operator-access

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

One in-VPC operator host per environment, reachable through AWS Systems Manager Session Manager only:

- private subnet, no public IP, no key pair, no inbound security group rule (Session Manager connects outbound);
- IMDSv2 required (hop limit 1), encrypted gp3 root volume (`kms_key_arn` or the account EBS default key);
- instance role with `AmazonSSMManagedInstanceCore` plus write access to its own session log group; operators get
  their database credential through [`operator-db-access`](../operator-db-access/README.md) roles, never through
  the instance role;
- egress only to `egress_cidr_blocks` (normally the VPC CIDR) on 443 (SSM, KMS, Secrets Manager endpoints) and 5432.

A service database admits the host by adding `operator_security_group_id` to the `aurora-postgresql`
`allowed_security_group_ids`.

## Session Manager logging (evidence trail)

With `session_logging_enabled` (default `true`) the module creates a rotating CMK (`alias/<name>-ssm-sessions`, key
policy: account administration plus CloudWatch Logs for this one log group only) and the log group
`/aws/ssm/<name>/sessions` encrypted with it (`session_log_retention_days`, default 365), and lets the instance role
write that group and use the key for session encryption. `manage_session_manager_preferences = true` also creates the
Session Manager preferences document `SSM-SessionManagerRunShell` (one per account and region, so off by default):
CloudWatch streaming to that group with encryption required, session data encrypted with the CMK, idle timeout
`session_idle_timeout_minutes`, no run-as.

What the trail contains:

- shell sessions on the host: the full transcript in the encrypted log group;
- port-forwarding sessions (`AWS-StartPortForwardingSessionToRemoteHost`, the normal database path): no transcript
  (the stream is the TLS-encrypted PostgreSQL protocol); the record is the CloudTrail `StartSession` event, which
  names the caller's role session and source identity, plus the database's own pgaudit lines in its `postgresql` log
  group;
- the credential read: CloudTrail `GetSecretValue` on `<env>/<slug>/db-import` with the same source identity.

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
| `session_logging_enabled` | `bool` | `true` | KMS-encrypted session log group and the host's write access. |
| `session_log_retention_days` | `number` | `365` | Session log retention. |
| `manage_session_manager_preferences` | `bool` | `false` | Own `SSM-SessionManagerRunShell` (account/region singleton). |
| `session_idle_timeout_minutes` | `number` | `20` | Idle timeout in the preferences document (1..60). |

## Outputs

| Name | Description |
|---|---|
| `operator_security_group_id` | Security group of the host. |
| `instance_id` | Target of `aws ssm start-session`. |
| `instance_role_arn` | Instance role. |
| `session_log_group_name` | Encrypted session log group (null when off). |
| `session_log_kms_key_arn` | CMK of session logs and session data (null when off). |

## Tests

`tests/host.tftest.hcl` (mock provider, `command = plan`): no public IP, IMDSv2, encrypted root volume, private
subnet, egress 443/5432 inside the VPC CIDR only, SSM core policy; `0.0.0.0/0` rejected; session log group encrypted
with a rotating untagged CMK, preferences document opt-in and pointing at that group and key (`command = apply`).
