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

module "irsa" {
  source = "../../modules/irsa-role"

  role_name         = "dev-loan-lifecycle-service-irsa"
  oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "https://oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  service_accounts  = [{ namespace = "lending", name = "loan-lifecycle-service" }]
  policy_arns = {
    runtime = "arn:aws:iam::111122223333:policy/dev-loan-lifecycle-service-runtime-access"
  }
}

output "role_arn" {
  value = module.irsa.role_arn
}
