output "cluster_name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group, attached to managed nodes. Services pass it as workload_security_group_id."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (services: eks_oidc_provider_arn)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer without https:// (services: eks_oidc_provider_url)."
  value       = local.oidc_issuer
}

output "kms_key_arn" {
  description = "KMS key used for secrets encryption and node volumes."
  value       = local.kms_key_arn
}

output "node_role_arn" {
  description = "Node IAM role ARN."
  value       = aws_iam_role.node.arn
}
