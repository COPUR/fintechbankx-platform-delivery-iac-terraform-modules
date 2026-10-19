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

module "network" {
  source = "../../modules/network-vpc"

  name             = "fintechbankx-dev"
  cidr_block       = "10.40.0.0/16"
  eks_cluster_name = "fintechbankx-dev"
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}
