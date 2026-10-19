# Offline (mock providers, no credentials): the github_services map of every
# tfvars example. scripts/ci/terraform-validate-all.sh runs this directory once
# per example:
#   terraform test -test-directory=tests/environments -var-file=environments/<env>.tfvars.example
# so every value below comes from that example, except the two inputs this
# file pins: the live state-bucket policy check (it reads the bucket; covered
# in modules/github-oidc/tests) and the Grafana database (its prod gate is
# covered in tests/grafana_db_gate.tftest.hcl). A plain `terraform test` does
# not read this directory.

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
  mock_data "aws_availability_zones" {
    defaults = { names = ["me-central-1a", "me-central-1b", "me-central-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0", insecure_value = "ami-0123456789abcdef0" }
  }
}

mock_provider "tls" {}

# Known policy JSON for the observability IRSA roles (bucket ARNs are unknown
# at plan and modules/irsa-role counts on the JSON).
override_data {
  target = data.aws_iam_policy_document.obs_storage["tempo"]
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

override_data {
  target = data.aws_iam_policy_document.obs_storage["loki"]
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

variables {
  verify_terraform_state_bucket_policy = false
  create_grafana_database              = false
}

# Same services in every environment (README "Image names"); a service added
# to one example only fails here for the others.
run "every_environment_lists_the_platform_services" {
  command = plan

  assert {
    condition = toset(keys(var.github_services)) == toset([
      "svc-acc-accounts-ledger",
      "svc-ln-loan-lifecycle",
      "svc-pay-initiation-settlement",
      "svc-pay-request-to-pay",
      "svc-pay-recurring-mandates",
      "svc-pay-bulk-orchestration",
      "svc-cus-profile-kyc",
      "svc-rsk-decisioning",
      "svc-cmp-evidence",
      "svc-of-consent-authorization",
      "svc-of-payee-verification",
      "svc-of-personal-financial-data",
      "svc-of-business-financial-data",
      "svc-of-banking-metadata",
      "svc-of-atm-directory",
      "svc-of-open-products-catalog",
    ])
    error_message = "github_services in ${var.environment}.tfvars.example does not list exactly the 16 platform services."
  }

  assert {
    condition     = alltrue([for id, s in var.github_services : s.terraform_state_key == "${s.namespace}/${s.image_name}/terraform.tfstate"])
    error_message = "Each service's state key is <namespace>/<image_name>/terraform.tfstate, the key in its deploy/terraform backend example."
  }

  assert {
    condition     = alltrue([for id, s in var.github_services : local.ecr_images[id] == s.image_name])
    error_message = "Every service gets its ECR repository fintechbankx/<image_name>."
  }

  assert {
    condition     = output.deploy_kubernetes_groups == { for id, s in var.github_services : id => "fintechbankx:deploy:${s.namespace}" }
    error_message = "Every service's deploy role maps to the deploy group of its own namespace."
  }
}

# Accounts ledger (repository COPUR/neo-fintechbankx-corebanking-accounts-ledger-service,
# chart deploy/helm/accounts-ledger-service, deploy/terraform backend key
# corebanking/accounts-ledger-service/terraform.tfstate). The repository name
# keeps its neo- prefix: GitHub OIDC subjects carry it verbatim.
run "accounts_ledger_is_wired" {
  command = plan

  assert {
    condition = (
      try(var.github_services["svc-acc-accounts-ledger"].repository, null) == "neo-fintechbankx-corebanking-accounts-ledger-service" &&
      try(var.github_services["svc-acc-accounts-ledger"].image_name, null) == "accounts-ledger-service" &&
      try(var.github_services["svc-acc-accounts-ledger"].namespace, null) == "corebanking" &&
      try(var.github_services["svc-acc-accounts-ledger"].terraform_state_key, null) == "corebanking/accounts-ledger-service/terraform.tfstate" &&
      try(var.github_services["svc-acc-accounts-ledger"].resource_name_prefix, "missing") == null
    )
    error_message = "svc-acc-accounts-ledger must be neo-fintechbankx-corebanking-accounts-ledger-service, image accounts-ledger-service, namespace corebanking, state key corebanking/accounts-ledger-service/terraform.tfstate, default resource prefix (<env>-accounts-ledger-service)."
  }

  assert {
    condition     = try(local.ecr_images["svc-acc-accounts-ledger"], null) == "accounts-ledger-service"
    error_message = "The ledger image is pushed to fintechbankx/accounts-ledger-service."
  }

  assert {
    condition     = try(output.deploy_kubernetes_groups["svc-acc-accounts-ledger"], null) == "fintechbankx:deploy:corebanking"
    error_message = "The ledger's deploy role maps to fintechbankx:deploy:corebanking."
  }
}
