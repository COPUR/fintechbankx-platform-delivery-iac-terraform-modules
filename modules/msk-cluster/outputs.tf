output "cluster_arn" {
  description = "MSK cluster ARN (input to msk-client-access)."
  value       = aws_msk_cluster.this.arn
}

output "cluster_name" {
  description = "MSK cluster name."
  value       = aws_msk_cluster.this.cluster_name
}

output "bootstrap_brokers_sasl_iam" {
  description = "Bootstrap brokers for SASL_SSL / AWS_MSK_IAM clients (port 9098)."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "security_group_id" {
  description = "Broker security group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "Encryption-at-rest key."
  value       = local.kms_key_arn
}

output "configuration_arn" {
  description = "Broker configuration ARN."
  value       = aws_msk_configuration.this.arn
}

output "topic_admin_policy_arn" {
  description = "Attach to the IRSA role of the topic provisioning job (CreateTopic/AlterTopic/DescribeTopic on evt.*, no delete)."
  value       = var.create_topic_admin_policy ? aws_iam_policy.topic_admin[0].arn : null
}

output "subnet_ids" {
  description = "Client subnets of the brokers."
  value       = var.subnet_ids
}
