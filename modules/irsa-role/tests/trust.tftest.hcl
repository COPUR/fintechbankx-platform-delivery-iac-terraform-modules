# Offline (mock provider): trust is limited to the listed service accounts.

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
  role_name         = "fintechbankx-dev-obs-tempo"
  oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "https://oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  service_accounts  = [{ namespace = "observability", name = "tempo" }]
}

run "trust_subject_and_audience" {
  command = plan

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust.statement).condition : tolist(c.values) if c.variable == "oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE:sub"])) == toset(["system:serviceaccount:observability:tempo"])
    error_message = "sub must be exactly system:serviceaccount:observability:tempo."
  }

  assert {
    condition     = toset(flatten([for c in one(data.aws_iam_policy_document.trust.statement).condition : tolist(c.values) if c.variable == "oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE:aud"])) == toset(["sts.amazonaws.com"])
    error_message = "aud must be sts.amazonaws.com."
  }
}

run "wildcard_service_account_rejected" {
  command = plan

  variables {
    service_accounts = [{ namespace = "observability", name = "*" }]
  }

  expect_failures = [var.service_accounts]
}

# The inline policy count must not depend on the policy JSON when the caller
# says whether to attach it (the JSON may be unknown until apply).
run "explicit_attach_flag_decides_the_inline_policy" {
  command = plan

  variables {
    inline_policy_json   = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    attach_inline_policy = false
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "attach_inline_policy = false attaches nothing."
  }
}

run "inline_policy_derived_without_flag" {
  command = plan

  variables {
    inline_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 1
    error_message = "Without the flag a non-null inline_policy_json is attached."
  }
}
