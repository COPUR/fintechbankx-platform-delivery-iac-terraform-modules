terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}

provider "aws" {
  region = "me-central-1"
}

# New-style caller: IRSA trust instead of ecs-tasks, KMS-encrypted runtime
# secret named under <env>/ so the aws-secrets-manager ClusterSecretStore can
# sync it.
module "service_base" {
  source = "../../modules/microservice-base"

  service_name               = "Loan Lifecycle Service"
  service_slug               = "loan-lifecycle-service"
  environment                = "dev"
  database_engine            = "aurora-postgresql"
  cache_engine               = "none"
  identity_provider_url      = "https://identity.dev.example.internal/realms/fintechbankx"
  observability_endpoint     = "http://otel-collector.observability.svc.cluster.local:4318"
  parameter_prefix           = "/fintechbankx"
  runtime_secret_name        = "dev/loan-lifecycle-service/runtime"
  kms_key_arn                = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-0000-0000-000000000000"
  eks_oidc_provider_arn      = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  eks_oidc_provider_url      = "oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  kubernetes_namespace       = "lending"
  kubernetes_service_account = "loan-lifecycle-service"
}

output "workload_role_arn" {
  value = module.service_base.workload_role_arn
}

output "runtime_access_policy_arn" {
  value = module.service_base.runtime_access_policy_arn
}
