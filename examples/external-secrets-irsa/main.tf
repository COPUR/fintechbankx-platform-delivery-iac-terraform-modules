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

module "external_secrets" {
  source = "../../modules/external-secrets-irsa"

  cluster_name      = "fintechbankx-dev"
  environment       = "dev"
  oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
}

output "role_arn" {
  value = module.external_secrets.role_arn
}
