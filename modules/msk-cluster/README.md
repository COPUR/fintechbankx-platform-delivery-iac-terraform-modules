# msk-cluster

Status: **Proposed** (validated with `terraform validate`; not applied anywhere).

Amazon MSK (provisioned) for the FinTechBankX event backbone:
- brokers spread evenly over the private subnets (one AZ each)
- TLS only between clients and brokers and inside the cluster
- IAM client authentication (SASL/AWS_MSK_IAM, port 9098); no plaintext,
no unauthenticated access
- KMS encryption at rest with a dedicated key
- topics are created explicitly (auto.create.topics.enable=false) by the
event-streaming repo; defaults RF 3 / min.insync.replicas 2
- broker logs in CloudWatch, Prometheus JMX/node exporters for scraping

## Usage

```hcl
module "msk_cluster" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/msk-cluster?ref=main"
  # inputs below
}
```

Examples: [`examples/msk-cluster`](../../examples/msk-cluster/main.tf).

## Requirements

- Terraform `>= 1.6.0`
- `hashicorp/aws` `>= 5.40, < 6.0`

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | required | MSK cluster name, e.g. fintechbankx-prod-events. |
| `kafka_version` | `string` | `"3.6.0"` | Apache Kafka version supported by Amazon MSK (contract: 3.6+). |
| `number_of_broker_nodes` | `number` | `3` | Broker count; a multiple of the subnet (AZ) count. 3 = one broker per AZ. |
| `broker_instance_type` | `string` | `"kafka.m7g.large"` | Broker instance type. |
| `broker_volume_size_gb` | `number` | `500` | EBS volume per broker in GiB. |
| `provisioned_throughput_mibps` | `number` | `null` | Optional EBS provisioned throughput per broker (MiB/s); null disables. |
| `vpc_id` | `string` | required | VPC id. |
| `subnet_ids` | `list(string)` | required | Private subnets, one per AZ (2 or 3). |
| `client_security_group_ids` | `list(string)` | `[]` | Security groups allowed to connect on 9098 (EKS cluster/node security group). |
| `monitoring_security_group_ids` | `list(string)` | `[]` | Security groups allowed to scrape exporters on 11001-11002. |
| `enable_open_monitoring` | `bool` | `true` | Enable Prometheus JMX and node exporters. |
| `enhanced_monitoring` | `string` | `"PER_TOPIC_PER_BROKER"` | CloudWatch enhanced monitoring level. |
| `server_properties_overrides` | `map(string)` | `{}` | Extra or overriding broker properties. auto.create.topics.enable, default.replication.factor and min.insync.replicas cannot be weakened. |
| `kms_key_arn` | `string` | `null` | Existing KMS key for encryption at rest. null creates a dedicated key. |
| `log_retention_days` | `number` | `30` | Broker log retention in CloudWatch. |
| `log_group_kms_key_arn` | `string` | `null` | Optional KMS key for the broker log group. |
| `alarm_topic_arn` | `string` | `null` | SNS topic for alarms; null disables notifications. |
| `tags` | `map(string)` | `{}` | Resource tags. |
| `create_topic_admin_policy` | `bool` | `true` | Create the topic-admin IAM policy for the topic provisioning job. |
| `topic_admin_prefixes` | `list(string)` | `["evt."]` | Topic name prefixes the provisioning job may create and alter. |

## Outputs

| Name | Description |
|---|---|
| `cluster_arn` | MSK cluster ARN (input to msk-client-access). |
| `cluster_name` | MSK cluster name. |
| `bootstrap_brokers_sasl_iam` | Bootstrap brokers for SASL_SSL / AWS_MSK_IAM clients (port 9098). |
| `security_group_id` | Broker security group. |
| `kms_key_arn` | Encryption-at-rest key. |
| `configuration_arn` | Broker configuration ARN. |
| `topic_admin_policy_arn` | Attach to the IRSA role of the topic provisioning job (CreateTopic/AlterTopic/DescribeTopic on evt.*, no delete). |
| `subnet_ids` | Client subnets of the brokers. |
