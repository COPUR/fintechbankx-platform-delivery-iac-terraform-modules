terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = "me-central-1"
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name            = "fintechbankx-dev"
  subnet_ids              = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"]
  cluster_admin_role_arns = ["arn:aws:iam::111122223333:role/platform-admin"]
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}
