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

module "redis" {
  source = "../../modules/elasticache-redis"

  environment                = "dev"
  service_slug               = "banking-metadata-service"
  name                       = "dev-of-banking-metadata"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
}

output "primary_endpoint" {
  value = module.redis.primary_endpoint
}
