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

module "pfd_docdb" {
  source = "../../modules/documentdb-cluster"

  environment                = "dev"
  service_slug               = "openfinance-personal-financial-data-service"
  name                       = "dev-of-personal-financial-data"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  instance_class             = "db.t4g.medium"
  instance_count             = 1
  deletion_protection        = false
}

output "app_secret_name" {
  value = module.pfd_docdb.app_secret_name
}
