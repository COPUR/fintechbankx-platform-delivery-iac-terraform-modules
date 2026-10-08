# Offline test (mock provider, no credentials): CI role names stay within the
# 64-character IAM limit and follow gha-<env>-<service id without svc->-<kind>.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "me-central-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  environment            = "staging"
  eks_cluster_name       = "fintechbankx-staging"
  terraform_state_bucket = "fintechbankx-terraform-state-staging"
}

run "longest_platform_service_ids_fit" {
  command = plan

  variables {
    services = {
      "svc-pay-initiation-settlement" = {
        repository          = "fintechbankx-lendingpayments-payment-orchestration-initiation-settlement"
        image_name          = "payment-initiation-settlement-service"
        namespace           = "payments"
        terraform_state_key = "payments/payment-initiation-settlement-service/terraform.tfstate"
      }
      "svc-of-business-financial-data" = {
        repository          = "fintechbankx-openfinance-corporate-data-business-financial"
        image_name          = "business-financial-data-service"
        namespace           = "open-finance"
        terraform_state_key = "open-finance/business-financial-data-service/terraform.tfstate"
      }
      "svc-abcdefgh-abcdefghijklmnopqrstuvwxyzabc" = {
        repository          = "max-length-id"
        image_name          = "max-length-service"
        namespace           = "lending"
        terraform_state_key = "lending/max-length-service/terraform.tfstate"
      }
    }
  }

  assert {
    condition     = alltrue([for n in values(local.role_names) : length(n) <= 64])
    error_message = "A CI role name exceeds 64 characters."
  }

  assert {
    condition     = local.role_names["svc-of-business-financial-data/tf-apply"] == "gha-staging-of-business-financial-data-tf-apply"
    error_message = "Unexpected role name pattern."
  }

  assert {
    condition     = length(local.role_sets) == 12
    error_message = "Expected four roles per service."
  }

  assert {
    condition     = aws_eks_access_entry.deploy["svc-of-business-financial-data/deploy"].kubernetes_groups == toset(["fintechbankx:deploy:open-finance"])
    error_message = "Deploy role must map to the namespaced deploy group."
  }
}

run "overlong_service_id_rejected" {
  command = plan

  variables {
    services = {
      "svc-abcdefgh-abcdefghijklmnopqrstuvwxyzabcd" = {
        repository          = "too-long"
        image_name          = "too-long-service"
        namespace           = "lending"
        terraform_state_key = "lending/too-long-service/terraform.tfstate"
      }
    }
  }

  expect_failures = [var.services]
}

run "sub_conditions_per_role_kind" {
  command = plan

  variables {
    environment = "prod"
    services = {
      "svc-ln-loan-lifecycle" = {
        repository          = "fintechbankx-lendingpayments-loan-lifecycle-core"
        image_name          = "loan-lifecycle-service"
        namespace           = "lending"
        terraform_state_key = "lending/loan-lifecycle-service/terraform.tfstate"
      }
    }
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/ecr-push"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:ref:refs/heads/main"])
    error_message = "ecr-push must trust only the main branch."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/deploy"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:environment:prod"])
    error_message = "deploy must trust only the prod GitHub environment."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/tf-apply"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:environment:prod"])
    error_message = "tf-apply must trust only the prod GitHub environment."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/tf-plan"].statement).condition : c.values if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:pull_request", "repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:ref:refs/heads/main"])
    error_message = "tf-plan must trust pull requests and main only."
  }

  assert {
    condition     = alltrue([for k, d in data.aws_iam_policy_document.trust : alltrue([for c in one(d.statement).condition : !strcontains(join(",", c.values), "*")])])
    error_message = "No trust condition may contain a wildcard."
  }
}
