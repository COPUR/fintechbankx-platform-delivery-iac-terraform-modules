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

module "msk" {
  source = "../../modules/msk-cluster"

  cluster_name              = "fintechbankx-dev-events"
  vpc_id                    = "vpc-0123456789abcdef0"
  subnet_ids                = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2", "subnet-0aaaaaaaaaaaaaaa3"]
  client_security_group_ids = ["sg-0123456789abcdef0"]
  broker_instance_type      = "kafka.t3.small"
  broker_volume_size_gb     = 100
}

output "bootstrap_brokers_sasl_iam" {
  value = module.msk.bootstrap_brokers_sasl_iam
}
