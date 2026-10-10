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

module "ecr" {
  source = "../../modules/ecr-repository"

  name = "fintechbankx/loan-lifecycle-service"
}

output "repository_url" {
  value = module.ecr.repository_url
}
