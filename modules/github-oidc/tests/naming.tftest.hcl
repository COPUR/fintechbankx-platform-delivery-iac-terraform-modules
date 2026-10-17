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

# The accounts ledger's repository name carries a neo- prefix and its
# namespace (corebanking) is new. Both are plain names for the services
# validation, and every trust subject, deploy group, state key and plan scope
# uses them verbatim; the slug (image_name) scopes its secrets
# <env>/accounts-ledger-service/* (db-app, db-migration).
run "neo_prefixed_repository_in_a_new_namespace" {
  command = plan

  variables {
    environment = "prod"
    services = {
      "svc-acc-accounts-ledger" = {
        repository          = "neo-fintechbankx-corebanking-accounts-ledger-service"
        image_name          = "accounts-ledger-service"
        namespace           = "corebanking"
        terraform_state_key = "corebanking/accounts-ledger-service/terraform.tfstate"
      }
    }
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-acc-accounts-ledger/ecr-push"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/neo-fintechbankx-corebanking-accounts-ledger-service:ref:refs/heads/main"])
    error_message = "ecr-push must trust the main branch of the neo- repository, name unchanged."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-acc-accounts-ledger/deploy"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/neo-fintechbankx-corebanking-accounts-ledger-service:environment:prod"])
    error_message = "deploy must trust only the prod GitHub environment of the neo- repository."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust["svc-acc-accounts-ledger/tf-plan"].statement).condition : tolist(c.values) if endswith(c.variable, ":sub")])) == toset(["repo:COPUR/neo-fintechbankx-corebanking-accounts-ledger-service:pull_request", "repo:COPUR/neo-fintechbankx-corebanking-accounts-ledger-service:ref:refs/heads/main"])
    error_message = "tf-plan must trust pull requests and main of the neo- repository only."
  }

  assert {
    condition     = [for k in ["ecr-push", "deploy", "tf-plan", "tf-apply"] : local.role_names["svc-acc-accounts-ledger/${k}"]] == ["gha-prod-acc-accounts-ledger-ecr-push", "gha-prod-acc-accounts-ledger-deploy", "gha-prod-acc-accounts-ledger-tf-plan", "gha-prod-acc-accounts-ledger-tf-apply"]
    error_message = "CI role names follow gha-<env>-<service id without svc->-<kind>."
  }

  assert {
    condition     = aws_eks_access_entry.deploy["svc-acc-accounts-ledger/deploy"].kubernetes_groups == toset(["fintechbankx:deploy:corebanking"])
    error_message = "The deploy role maps to the deploy group of the corebanking namespace."
  }

  assert {
    condition     = aws_iam_role.this["svc-acc-accounts-ledger/tf-apply"].tags["TerraformStateKey"] == "corebanking/accounts-ledger-service/terraform.tfstate"
    error_message = "tf-apply carries the ledger's own state key."
  }

  assert {
    condition     = toset(one([for st in data.aws_iam_policy_document.ecr_push["svc-acc-accounts-ledger/ecr-push"].statement : st.resources if st.sid == "PushPullOwnRepository"])) == toset(["arn:aws:ecr:me-central-1:111122223333:repository/fintechbankx/accounts-ledger-service"])
    error_message = "ecr-push may push only fintechbankx/accounts-ledger-service."
  }

  assert {
    condition     = contains(tolist(one([for st in data.aws_iam_policy_document.plan_read["svc-acc-accounts-ledger/tf-plan"].statement : st.resources if st.sid == "OwnSecrets"])), "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/accounts-ledger-service/*")
    error_message = "The plan role describes the ledger's own secrets under prod/accounts-ledger-service/."
  }
}
