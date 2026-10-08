# msk-client-access

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Topic-scoped Amazon MSK IAM policy for one service (contract: SASL_SSL with
AWS_MSK_IAM through the service's IRSA role).
- produce: the service's own evt.<ctx>.<aggregate>.* namespaces
(produce_topic_prefixes) and exact topics (produce_topics, e.g. the DLQ
of another namespace it consumes)
- consume: only the listed topics, only with its own consumer groups
cg.<service-id>.<purpose>.v<major> (consumer_groups) or the prefix
cg.<service-id>. (consumer_group_prefixes)
Input names follow topics/generated/msk-client-access.json in
fintechbankx-platform-event-streaming-kafka.
Topic creation and configuration stay with the event-streaming repo; this
policy grants no CreateTopic/AlterTopic/DeleteTopic.

## Usage

```hcl
module "msk_client_access" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/msk-client-access?ref=main"
  # inputs below
}
```

Examples: [`examples/msk-client-access`](../../examples/msk-client-access/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `service_id` | `string` | required | Service id (svc-<ctx>-<cap>), used in descriptions. |
| `policy_name` | `string` | required | IAM policy name, e.g. <env>-<service-slug>-msk. |
| `cluster_arn` | `string` | required | MSK cluster ARN (msk-cluster output cluster_arn). |
| `produce_topic_prefixes` | `list(string)` | `[]` | The service's own aggregates as evt.<ctx>.<aggregate>. prefixes (e.g. ["evt.ln.loan."]). |
| `produce_topics` | `list(string)` | `[]` | Exact topics the service writes, evt.<ctx>.<aggregate>.<event>.v<major> (e.g. the DLQ evt.<ctx>.<aggregate>.dlq.v1 of a namespace it consumes). |
| `consume_topics` | `list(string)` | `[]` | Topics the service consumes, full names (evt.<ctx>.<aggregate>.<event>.v<major>) or an aggregate prefix ending in .* . |
| `consumer_groups` | `list(string)` | `[]` | Declared consumer groups cg.<service-id>.<purpose>.v<major>. |
| `consumer_group_prefixes` | `list(string)` | `[]` | Optional prefix form cg.<service-id>. (covers every group of the service). |
| `transactional_id_prefixes` | `list(string)` | `[]` | Optional transactional.id prefixes for transactional producers (normally the service id). |
| `attach_to_role_names` | `list(string)` | `[]` | IAM role names (e.g. the service's IRSA role) to attach the policy to. |
| `tags` | `map(string)` | `{}` | Resource tags. |

## Outputs

| Name | Description |
|---|---|
| `policy_arn` | Managed policy ARN to attach to the service's IRSA role. |
| `policy_json` | Rendered policy document (for review and tests). |

## Inputs from the topic catalog

`fintechbankx-platform-event-streaming-kafka` renders `topics/generated/msk-client-access.json`; its per-service fields
map one to one onto this module: `produce_topics`, `produce_topic_prefixes`, `consume_topics`, `consumer_groups`
(`cg.<service-id>.<purpose>.v<major>`) and `consumer_group_prefixes` (`cg.<service-id>.`). Consumer groups must
start with `cg.<service_id>.` (plan-time precondition). The policy never grants `CreateTopic`, `AlterTopic` or
`DeleteTopic`; the topic provisioning job uses `topic_admin_policy_arn` from `msk-cluster`.
