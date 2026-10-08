# Offline test (mock provider, no credentials): the tf-plan role can decrypt
# its own Terraform-written secrets when they use a customer managed key
# (documentdb-cluster, elasticache-redis, microservice-base with kms_key_arn),
# and only through Secrets Manager for its own secret ARNs. Not every service
# key has an alias (elasticache-redis creates none; microservice-base takes the
# caller's key), so the scope is the SecretARN encryption context, not an alias.

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
  services = {
    "svc-ln-loan-lifecycle" = {
      repository          = "fintechbankx-lendingpayments-loan-lifecycle-core"
      image_name          = "loan-lifecycle-service"
      namespace           = "lending"
      terraform_state_key = "lending/loan-lifecycle-service/terraform.tfstate"
    }
  }
}

run "plan_role_decrypts_only_its_own_secrets_via_secrets_manager" {
  command = plan

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : st
      if contains(st.actions, "kms:Decrypt")
    ]) == 1
    error_message = "The plan role needs exactly one kms:Decrypt statement for its CMK-encrypted secrets."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement :
      toset(st.actions) == toset(["kms:Decrypt"]) &&
      toset(st.resources) == toset(["arn:aws:kms:me-central-1:111122223333:key/*"]) &&
      length([for c in st.condition : c if c.test == "StringEquals" && c.variable == "kms:ViaService" && toset(c.values) == toset(["secretsmanager.me-central-1.amazonaws.com"])]) == 1 &&
      length([for c in st.condition : c if c.test == "StringLike" && c.variable == "kms:EncryptionContext:SecretARN" && toset(c.values) == toset([
        "arn:aws:secretsmanager:me-central-1:111122223333:secret:staging/loan-lifecycle-service/*",
        "arn:aws:secretsmanager:me-central-1:111122223333:secret:staging-loan-lifecycle-service/*",
      ])]) == 1 &&
      length(st.condition) == 2
      if contains(st.actions, "kms:Decrypt")
    ])
    error_message = "kms:Decrypt must be limited to Secrets Manager (kms:ViaService) and the service's own secret ARNs (kms:EncryptionContext:SecretARN)."
  }
}
