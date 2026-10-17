# Offline test (mock provider): with workflow binding on, every CI role trusts
# only the platform's own reusable workflow at a release ref
# (job_workflow_ref in the customized sub claim), so a caller cannot run a
# modified copy of helm-deploy with the deploy role. Off by default.

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
  environment                 = "staging"
  eks_cluster_name            = "fintechbankx-staging"
  terraform_state_bucket      = "fintechbankx-terraform-state-staging"
  terraform_state_kms_key_arn = "arn:aws:kms:me-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  apply_policy_arns           = ["arn:aws:iam::111122223333:policy/fintechbankx-ci-apply-lending"]
  services = {
    "svc-ln-loan-lifecycle" = {
      repository          = "fintechbankx-lendingpayments-loan-lifecycle-core"
      image_name          = "loan-lifecycle-service"
      namespace           = "lending"
      terraform_state_key = "lending/loan-lifecycle-service/terraform.tfstate"
    }
    "svc-pay-initiation-settlement" = {
      repository          = "fintechbankx-lendingpayments-payment-orchestration-initiation-settlement"
      image_name          = "payment-initiation-settlement-service"
      namespace           = "payments"
      terraform_state_key = "payments/payment-initiation-settlement-service/terraform.tfstate"
    }
  }
}


run "binding_off_keeps_plain_subjects" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for k, d in data.aws_iam_policy_document.trust : [
        for st in d.statement : [for c in st.condition : !strcontains(join(",", c.values), "job_workflow_ref") if c.variable == "token.actions.githubusercontent.com:sub"]
      ]
    ]))
    error_message = "Without bind_platform_workflow_ref the subjects stay unchanged."
  }
}

run "binding_on_pins_each_role_to_its_platform_workflow" {
  command = plan

  variables {
    bind_platform_workflow_ref = true
  }

  assert {
    condition = toset(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/deploy"].statement : [
        for c in st.condition : c.values if c.variable == "token.actions.githubusercontent.com:sub"
      ]
    ])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:environment:staging:job_workflow_ref:COPUR/fintechbankx-platform-delivery-iac-cicd-templates/.github/workflows/helm-deploy.yml@refs/tags/v*"])
    error_message = "deploy must trust only helm-deploy.yml from the platform repo at a release tag."
  }

  assert {
    condition = alltrue(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/deploy"].statement : [
        for c in st.condition : c.test == "StringLike" if c.variable == "token.actions.githubusercontent.com:sub"
      ]
    ]))
    error_message = "The ref pattern needs StringLike."
  }

  assert {
    condition = alltrue(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/ecr-push"].statement : [
        for c in st.condition : alltrue([for v in c.values : endswith(v, ":job_workflow_ref:COPUR/fintechbankx-platform-delivery-iac-cicd-templates/.github/workflows/container-image.yml@refs/tags/v*")]) if c.variable == "token.actions.githubusercontent.com:sub"
      ]
    ]))
    error_message = "ecr-push must trust only container-image.yml."
  }

  assert {
    condition = length(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/tf-plan"].statement : [
        for c in st.condition : c.values if c.variable == "token.actions.githubusercontent.com:sub"
      ]
      ])) == 2 && alltrue(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/tf-plan"].statement : [
        for c in st.condition : [for v in c.values : strcontains(v, "/.github/workflows/terraform.yml@refs/tags/v*")] if c.variable == "token.actions.githubusercontent.com:sub"
      ]
    ]))
    error_message = "tf-plan keeps its pull_request and main subjects, each bound to terraform.yml (a customized sub applies to every job in the repo)."
  }
}

run "release_shas_can_be_trusted" {
  command = plan

  variables {
    bind_platform_workflow_ref = true
    platform_workflow_refs     = ["0123456789abcdef0123456789abcdef01234567"]
  }

  assert {
    condition = toset(flatten([
      for st in data.aws_iam_policy_document.trust["svc-ln-loan-lifecycle/deploy"].statement : [
        for c in st.condition : c.values if c.variable == "token.actions.githubusercontent.com:sub"
      ]
    ])) == toset(["repo:COPUR/fintechbankx-lendingpayments-loan-lifecycle-core:environment:staging:job_workflow_ref:COPUR/fintechbankx-platform-delivery-iac-cicd-templates/.github/workflows/helm-deploy.yml@0123456789abcdef0123456789abcdef01234567"])
    error_message = "A caller pinning by SHA is trusted only at the listed release SHA."
  }
}

run "branch_refs_are_rejected" {
  command = plan

  variables {
    bind_platform_workflow_ref = true
    platform_workflow_refs     = ["refs/heads/main"]
  }

  expect_failures = [var.platform_workflow_refs]
}
