# Contract fixture: the exact microservice-base call made by the five service
# repos' deploy/terraform/main.tf (loan-lifecycle, initiation-settlement,
# profile-kyc, risk-decisioning, compliance-evidence) and the outputs they
# read. CI validates it so a breaking change to the module fails here first.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "aws" {
  region = "me-central-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

module "service_base" {
  source = "../../../modules/microservice-base"

  service_name           = "Loan Lifecycle Service"
  service_slug           = "loan-lifecycle-service"
  environment            = var.environment
  database_engine        = "aurora-postgresql"
  cache_engine           = "none"
  identity_provider_url  = "https://identity.dev.example.internal/realms/fintechbankx"
  observability_endpoint = "https://otel.dev.example.internal"
  parameter_prefix       = "/fintechbankx"
  log_retention_days     = var.environment == "prod" ? 365 : 30
  tags                   = { Service = "svc-ln-loan-lifecycle" }
}

output "secret_arn" {
  value = module.service_base.secret_arn
}

output "log_group_name" {
  value = module.service_base.cloudwatch_log_group_name
}
