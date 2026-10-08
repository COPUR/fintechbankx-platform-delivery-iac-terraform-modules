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

# Database for svc-ln-loan-lifecycle (same shape as its deploy/terraform).
module "loan_db" {
  source = "../../modules/aurora-postgresql"

  name                       = "dev-loan-lifecycle-service"
  database_name              = "db_ln_loan_lifecycle_dev"
  master_username            = "loan_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/loan-lifecycle-service/db-app"
  instance_count             = 1
  max_capacity               = 2
  deletion_protection        = false
}

# Keycloak's database is the same module (no separate module).
module "keycloak_db" {
  source = "../../modules/aurora-postgresql"

  name                       = "dev-keycloak"
  database_name              = "db_iam_keycloak_dev"
  master_username            = "keycloak_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/keycloak/db-app"
}

output "jdbc_url" {
  value = module.loan_db.jdbc_url
}
