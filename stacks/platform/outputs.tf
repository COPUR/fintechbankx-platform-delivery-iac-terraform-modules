# Names match the inputs of the service repos' deploy/terraform.

output "vpc_id" {
  description = "Service input vpc_id."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Service input private_subnet_ids."
  value       = module.network.private_subnet_ids
}

output "intra_subnet_ids" {
  description = "Subnets without internet route."
  value       = module.network.intra_subnet_ids
}

output "workload_security_group_id" {
  description = "Service input workload_security_group_id (EKS cluster security group on managed nodes)."
  value       = module.eks.cluster_security_group_id
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "Service input eks_oidc_provider_arn."
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "Service input eks_oidc_provider_url."
  value       = module.eks.oidc_provider_url
}

output "msk_cluster_arn" {
  description = "Input to modules/msk-client-access."
  value       = module.msk.cluster_arn
}

output "msk_bootstrap_brokers_sasl_iam" {
  description = "KAFKA_BOOTSTRAP_SERVERS for SASL_SSL / AWS_MSK_IAM clients."
  value       = module.msk.bootstrap_brokers_sasl_iam
}

output "amp_remote_write_url" {
  description = "Remote write URL for the OTel collector."
  value       = module.observability.remote_write_url
}

output "grafana_endpoint" {
  description = "Managed Grafana URL (null when disabled)."
  value       = module.observability.grafana_endpoint
}

output "ecr_repository_urls" {
  description = "Service id -> Helm value image.repository."
  value       = { for k, m in module.ecr : k => m.repository_url }
}

output "external_secrets_role_arn" {
  description = "Annotate SA external-secrets/external-secrets (ClusterSecretStore aws-secrets-manager)."
  value       = module.external_secrets_irsa.role_arn
}

output "otel_collector_role_arn" {
  description = "Annotate the OTel collector service account."
  value       = module.otel_collector_irsa.role_arn
}

output "github_oidc_role_arns" {
  description = "Service id -> CI role ARNs (ecr-push, deploy, tf-plan, tf-apply) for the repository variables."
  value       = module.github_oidc.role_arns
}

output "deploy_kubernetes_groups" {
  description = "Service id -> Kubernetes group of its deploy role; bind to a namespaced Role."
  value       = module.github_oidc.deploy_kubernetes_groups
}

# --- Network facts for the mesh repo (params.env) -----------------------------

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = module.network.vpc_cidr_block
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs; Aurora clusters and MSK brokers live here."
  value       = module.network.private_subnet_cidrs
}

output "msk_security_group_id" {
  description = "MSK broker security group."
  value       = module.msk.security_group_id
}

output "msk_subnet_ids" {
  description = "Subnets of the MSK brokers."
  value       = module.msk.subnet_ids
}

output "msk_topic_admin_policy_arn" {
  description = "Attach to the topic provisioning job's IRSA role."
  value       = module.msk.topic_admin_policy_arn
}

output "ingress_tls_secret_name" {
  description = "Secrets Manager name the mesh repo syncs for the ingress gateway certificate (created and filled outside Terraform; no certificate material here)."
  value       = "${var.environment}/platform/ingress-tls"
}
