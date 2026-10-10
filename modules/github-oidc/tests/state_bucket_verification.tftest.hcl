# Offline test (mock provider, no credentials): when the state bucket is owned
# by a bootstrap outside this module, verify_terraform_state_bucket_policy reads
# the bucket's live policy and fails the plan unless the CI deny statements of
# terraform_state_bucket_policy_json have been merged into it. Without
# DenyCiTerraformRolesOtherStateObjects a CI role could read every service's
# state.

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

run "verification_is_off_by_default" {
  command = plan

  assert {
    condition     = length(data.aws_s3_bucket_policy.state) == 0 && length(aws_s3_bucket_policy.state) == 0
    error_message = "Without verify/manage the module neither reads nor writes the bucket policy."
  }
}

run "bucket_policy_without_ci_denies_fails_the_plan" {
  command = plan

  variables {
    verify_terraform_state_bucket_policy = true
  }

  override_data {
    target = data.aws_s3_bucket_policy.state[0]
    values = {
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"arn:aws:s3:::fintechbankx-terraform-state-staging/*\",\"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"
    }
  }

  expect_failures = [data.aws_s3_bucket_policy.state]
}

run "bucket_policy_with_only_some_ci_denies_fails_the_plan" {
  command = plan

  variables {
    verify_terraform_state_bucket_policy = true
  }

  override_data {
    target = data.aws_s3_bucket_policy.state[0]
    values = {
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyCiTerraformRolesWithoutStateKeyTag\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"*\"}]}"
    }
  }

  expect_failures = [data.aws_s3_bucket_policy.state]
}

run "allow_statement_with_the_right_sid_fails_the_plan" {
  command = plan

  variables {
    verify_terraform_state_bucket_policy = true
  }

  override_data {
    target = data.aws_s3_bucket_policy.state[0]
    values = {
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyCiTerraformRolesWithoutStateKeyTag\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesOtherStateObjects\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesBucketActionsExceptList\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"NotAction\":\"s3:ListBucket\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesListOutsideOwnKey\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:ListBucket\",\"Resource\":\"*\"}]}"
    }
  }

  expect_failures = [data.aws_s3_bucket_policy.state]
}

run "merged_bucket_policy_passes" {
  command = plan

  variables {
    verify_terraform_state_bucket_policy = true
  }

  override_data {
    target = data.aws_s3_bucket_policy.state[0]
    values = {
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyInsecureTransport\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesWithoutStateKeyTag\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesOtherStateObjects\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"NotResource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesBucketActionsExceptList\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"NotAction\":\"s3:ListBucket\",\"Resource\":\"*\"},{\"Sid\":\"DenyCiTerraformRolesListOutsideOwnKey\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:ListBucket\",\"Resource\":\"*\"}]}"
    }
  }

  assert {
    condition     = length(data.aws_s3_bucket_policy.state) == 1 && length(aws_s3_bucket_policy.state) == 0
    error_message = "With verification on and management off, the module reads the policy and does not write it."
  }
}

run "managed_policy_is_attached_not_read" {
  command = plan

  variables {
    verify_terraform_state_bucket_policy = true
    manage_terraform_state_bucket_policy = true
  }

  assert {
    condition     = length(data.aws_s3_bucket_policy.state) == 0 && length(aws_s3_bucket_policy.state) == 1
    error_message = "When the module attaches the policy itself there is nothing to verify before apply."
  }
}
