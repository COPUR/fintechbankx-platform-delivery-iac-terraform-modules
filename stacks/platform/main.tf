# Platform composition root for one environment (one cell, one region):
# VPC -> EKS (+ IRSA) -> MSK -> AMP (+ optional Grafana) -> ECR repositories,
# plus the IRSA roles of the platform operators (External Secrets, OTel
# collector). Service repos consume the outputs through their own
# deploy/terraform (vpc_id, private_subnet_ids, workload_security_group_id,
# eks_oidc_provider_arn/url, msk_cluster_arn).

locals {
  name = "${var.name_prefix}-${var.environment}"

  # ECR repositories: every github_services image plus any extra entries.
  ecr_images = merge({ for id, s in var.github_services : id => s.image_name }, var.service_repositories)

  tags = merge({
    Platform    = "fintechbankx"
    Environment = var.environment
    ManagedBy   = "terraform"
    Stack       = "platform"
    OwningSquad = "infrastructure-and-data-platform"
  }, var.tags)
}

module "network" {
  source = "../../modules/network-vpc"

  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  eks_cluster_name   = local.name
  tags               = local.tags
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name                 = local.name
  kubernetes_version           = var.kubernetes_version
  subnet_ids                   = module.network.private_subnet_ids
  endpoint_public_access       = var.eks_endpoint_public_access
  endpoint_public_access_cidrs = var.eks_endpoint_public_access_cidrs
  cluster_admin_role_arns      = var.eks_cluster_admin_role_arns
  node_groups                  = var.eks_node_groups
  log_retention_days           = var.log_retention_days
  tags                         = local.tags
}

module "msk" {
  source = "../../modules/msk-cluster"

  cluster_name                  = "${local.name}-events"
  kafka_version                 = var.kafka_version
  number_of_broker_nodes        = var.msk_broker_count
  broker_instance_type          = var.msk_broker_instance_type
  broker_volume_size_gb         = var.msk_broker_volume_size_gb
  vpc_id                        = module.network.vpc_id
  subnet_ids                    = module.network.private_subnet_ids
  client_security_group_ids     = [module.eks.cluster_security_group_id]
  monitoring_security_group_ids = [module.eks.cluster_security_group_id]
  log_retention_days            = var.log_retention_days
  alarm_topic_arn               = var.alarm_topic_arn
  tags                          = local.tags
}

module "observability" {
  source = "../../modules/observability-amp"

  name           = local.name
  enable_grafana = var.enable_managed_grafana
  tags           = local.tags
}

module "ecr" {
  source   = "../../modules/ecr-repository"
  for_each = var.create_ecr_repositories ? local.ecr_images : {}

  name = "fintechbankx/${each.value}"
  tags = merge(local.tags, { Service = each.key })
}

# --- Platform operator identities -------------------------------------------

module "external_secrets_irsa" {
  source = "../../modules/external-secrets-irsa"

  cluster_name      = module.eks.cluster_name
  environment       = var.environment
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.tags
}

module "otel_collector_irsa" {
  source = "../../modules/irsa-role"

  role_name         = "${local.name}-otel-collector"
  description       = "OTel collector / Prometheus remote write to AMP"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  service_accounts  = [var.otel_collector_service_account]
  policy_arns       = { amp_remote_write = module.observability.remote_write_policy_arn }
  tags              = local.tags
}

# --- CI/CD federation (GitHub Actions OIDC) ----------------------------------

module "github_oidc" {
  source = "../../modules/github-oidc"

  environment                 = var.environment
  create_oidc_provider        = var.create_github_oidc_provider
  oidc_provider_arn           = var.github_oidc_provider_arn
  services                    = var.github_services
  create_ecr_push_roles       = var.create_ecr_repositories
  eks_cluster_name            = module.eks.cluster_name
  terraform_state_bucket      = coalesce(var.terraform_state_bucket, "${var.name_prefix}-terraform-state-${var.environment}")
  terraform_lock_table        = var.terraform_lock_table
  terraform_state_kms_key_arn = var.terraform_state_kms_key_arn
  apply_policy_arns           = var.ci_apply_policy_arns
  permissions_boundary_arn    = var.ci_permissions_boundary_arn
  tags                        = local.tags
}
