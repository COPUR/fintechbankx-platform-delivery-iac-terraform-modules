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

module "github_oidc" {
  source = "../../modules/github-oidc"

  environment            = "dev"
  eks_cluster_name       = "fintechbankx-dev"
  terraform_state_bucket = "fintechbankx-terraform-state-dev"
  services = {
    "svc-ln-loan-lifecycle" = {
      repository          = "fintechbankx-lendingpayments-loan-lifecycle-core"
      image_name          = "loan-lifecycle-service"
      namespace           = "lending"
      terraform_state_key = "lending/loan-lifecycle-service/terraform.tfstate"
    }
  }
}

output "role_arns" {
  value = module.github_oidc.role_arns
}
