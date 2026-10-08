# Offline test (mock provider, no credentials): the pull_request-trusted
# tf-plan role is least privilege. No AWS-managed broad policies, no write
# actions beyond its own lock item, and S3/KMS/DynamoDB access limited to its
# own state key, so a pull request can never read another service's state.

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

run "plan_role_is_least_privilege" {
  command = plan

  # No AWS-managed broad policy on any role; nothing managed on plan roles.
  assert {
    condition = alltrue([for k, a in local.managed_policy_attachments :
      !can(regex(":iam::aws:policy/(AdministratorAccess|ReadOnlyAccess|PowerUserAccess|ViewOnlyAccess)$", a.policy_arn))
    ])
    error_message = "No github-oidc role may carry AdministratorAccess, ReadOnlyAccess, PowerUserAccess or ViewOnlyAccess."
  }

  assert {
    condition     = length([for k, a in local.managed_policy_attachments : k if endswith(a.role_key, "/tf-plan")]) == 0
    error_message = "tf-plan roles get only the module's inline policies, no managed policy attachments."
  }

  # Source guard: managed attachments exist only via local.managed_policy_attachments
  # (one resource), and the module never hard-codes an AWS-managed policy.
  assert {
    condition = (
      length(regexall("resource \"aws_iam_role_policy_attachment\"", file("${path.module}/main.tf"))) == 1 &&
      length(regexall("for_each += local.managed_policy_attachments", file("${path.module}/main.tf"))) == 1 &&
      !strcontains(file("${path.module}/main.tf"), "iam::aws:policy/")
    )
    error_message = "Managed policy attachments must go through local.managed_policy_attachments; no AWS-managed policy ARNs in the module."
  }

  # Every S3 statement of the plan role references only its own bucket/key.
  assert {
    condition = alltrue(flatten([
      for doc in [data.aws_iam_policy_document.state["svc-ln-loan-lifecycle/tf-plan"], data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"]] : [
        for st in doc.statement : [
          for r in st.resources : contains([
            "arn:aws:s3:::fintechbankx-terraform-state-staging",
            "arn:aws:s3:::fintechbankx-terraform-state-staging/lending/loan-lifecycle-service/terraform.tfstate",
          ], r)
        ] if anytrue([for a in st.actions : startswith(a, "s3:")])
      ]
    ]))
    error_message = "Plan-role S3 statements may reference only the bucket and the service's own state key."
  }

  assert {
    condition     = length([for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : st if anytrue([for a in st.actions : startswith(a, "s3:")])]) == 0
    error_message = "The plan read policy must not grant S3 at all (state access lives only in the state policy)."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.state["svc-ln-loan-lifecycle/tf-plan"].statement : alltrue([
        for c in st.condition : c.test == "StringEquals" && toset(c.values) == toset(["lending/loan-lifecycle-service/terraform.tfstate"])
        if c.variable == "s3:prefix"
      ]) && length([for c in st.condition : c if c.variable == "s3:prefix"]) == 1
      if contains(tolist(st.actions), "s3:ListBucket")
    ])
    error_message = "Plan-role ListBucket must be limited with StringEquals s3:prefix = its own state key."
  }

  # No write actions on the pull_request-trusted role except its own lock item.
  assert {
    condition = alltrue(flatten([
      for doc in [data.aws_iam_policy_document.state["svc-ln-loan-lifecycle/tf-plan"], data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"]] : [
        for st in doc.statement : [
          for a in st.actions : !can(regex("^[a-z0-9-]+:(Put|Delete|Create|Update|Modify|Attach|Detach|Tag|Untag|Pass|Encrypt|GenerateDataKey|ReEncrypt|Restore|Schedule|Rotate|Reboot|Start|Stop|Write|Set|Add|Remove|Revoke|Authorize|Replicate|Restore|Invoke|Execute)", a)) || (
            contains(["dynamodb:PutItem", "dynamodb:DeleteItem"], a) &&
            toset(st.resources) == toset(["arn:aws:dynamodb:me-central-1:111122223333:table/fintechbankx-terraform-locks"]) &&
            toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "dynamodb:LeadingKeys"])) == toset(["fintechbankx-terraform-state-staging/lending/loan-lifecycle-service/terraform.tfstate"])
          )
        ]
      ]
    ]))
    error_message = "The pull_request-trusted tf-plan role must have no write actions except PutItem/DeleteItem on its own lock item."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.state["svc-ln-loan-lifecycle/tf-plan"].statement : alltrue([
        for c in st.condition : !strcontains(join(",", c.values), "*") if c.variable == "dynamodb:LeadingKeys"
      ])
    ])
    error_message = "Lock-table LeadingKeys must be exact (no wildcard)."
  }

  # KMS on the state key only through S3 and only for this object.
  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.state["svc-ln-loan-lifecycle/tf-plan"].statement :
      toset(st.actions) == toset(["kms:Decrypt"]) &&
      toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "kms:ViaService"])) == toset(["s3.me-central-1.amazonaws.com"]) &&
      toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "kms:EncryptionContext:aws:s3:arn"])) == toset(["arn:aws:s3:::fintechbankx-terraform-state-staging/lending/loan-lifecycle-service/terraform.tfstate"])
      if anytrue([for a in st.actions : startswith(a, "kms:")])
    ])
    error_message = "Plan-role KMS must be Decrypt only, via S3, for its own state object."
  }

  # The read policy never names another service's resources and never reads data.
  assert {
    condition = alltrue(flatten([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : [
        for r in st.resources : !strcontains(r, "payment-initiation-settlement")
      ]
    ]))
    error_message = "loan-lifecycle plan role must not reference payment-initiation resources."
  }

  assert {
    condition = alltrue(flatten([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : [
        for a in st.actions : !contains(["logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery", "s3:GetObject", "dynamodb:Scan", "dynamodb:Query"], a)
      ]
    ]))
    error_message = "The plan read policy must not read log events or data."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : alltrue([
        for a in st.actions : can(regex("^[a-z0-9-]+:(Describe|List)", a))
      ]) if contains(tolist(st.resources), "*")
    ])
    error_message = "Unscoped (*) statements may only carry Describe/List actions."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.plan_read["svc-ln-loan-lifecycle/tf-plan"].statement : alltrue([
        for r in st.resources : strcontains(r, "staging/loan-lifecycle-service") || strcontains(r, "staging-loan-lifecycle-service")
      ]) if anytrue([for a in st.actions : startswith(a, "secretsmanager:")])
    ])
    error_message = "Secrets Manager access must be limited to the service's own secrets."
  }

  # The role carries its state key; the bucket policy keys off it.
  assert {
    condition     = aws_iam_role.this["svc-ln-loan-lifecycle/tf-plan"].tags["TerraformStateKey"] == "lending/loan-lifecycle-service/terraform.tfstate"
    error_message = "tf-plan role must be tagged with its own state key."
  }
}

run "state_bucket_policy_denies_other_keys" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.state_bucket.statement :
      st.effect == "Deny" &&
      contains(st.not_resources == null ? [] : tolist(st.not_resources), "arn:aws:s3:::fintechbankx-terraform-state-staging/$${aws:PrincipalTag/TerraformStateKey}") &&
      toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "aws:PrincipalArn"])) == toset([
        "arn:aws:iam::111122223333:role/gha-staging-*-tf-plan",
        "arn:aws:iam::111122223333:role/gha-staging-*-tf-apply",
      ])
    ])
    error_message = "State bucket policy must deny CI Terraform roles every object except their own state key."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.state_bucket.statement :
      st.effect == "Deny" && anytrue([for c in st.condition : c.test == "Null" && c.variable == "aws:PrincipalTag/TerraformStateKey" && toset(c.values) == toset(["true"])])
    ])
    error_message = "CI Terraform roles without a TerraformStateKey tag must be denied."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.state_bucket.statement :
      st.effect == "Deny" && contains(st.actions == null ? [] : tolist(st.actions), "s3:ListBucket") &&
      anytrue([for c in st.condition : c.test == "StringNotEquals" && c.variable == "s3:prefix"])
    ])
    error_message = "State bucket policy must deny listing outside the role's own key."
  }
}

run "duplicate_state_keys_rejected" {
  command = plan

  variables {
    services = {
      "svc-ln-loan-lifecycle" = {
        repository          = "a"
        image_name          = "loan-lifecycle-service"
        namespace           = "lending"
        terraform_state_key = "shared/terraform.tfstate"
      }
      "svc-ln-loan-origination" = {
        repository          = "b"
        image_name          = "loan-origination-service"
        namespace           = "lending"
        terraform_state_key = "shared/terraform.tfstate"
      }
    }
  }

  expect_failures = [var.services]
}

run "broad_managed_policy_rejected_for_apply" {
  command = plan

  variables {
    apply_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  }

  expect_failures = [var.apply_policy_arns]
}
