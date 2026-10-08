# Offline (mock provider): backward compatibility with the five service repos and IRSA trust.

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

mock_provider "random" {}

variables {
  service_name           = "Loan Lifecycle Service"
  service_slug           = "loan-lifecycle-service"
  environment            = "dev"
  database_engine        = "aurora-postgresql"
  cache_engine           = "none"
  identity_provider_url  = "https://identity.example/realms/fintechbankx"
  observability_endpoint = "http://otel-collector.observability:4317"
}

run "default_prefix_keeps_legacy_names" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.service.name == "/openfinance/dev/loan-lifecycle-service"
    error_message = "Default log group name changed; existing callers would replace their log group."
  }

  assert {
    condition     = aws_ssm_parameter.database_engine.name == "/openfinance/dev/loan-lifecycle-service/database_engine"
    error_message = "Default SSM path changed."
  }

  assert {
    condition     = aws_secretsmanager_secret.service_runtime.name == "dev-loan-lifecycle-service/runtime"
    error_message = "Default runtime secret name changed."
  }

  assert {
    condition     = one(data.aws_iam_policy_document.workload_assume_role.statement).actions == toset(["sts:AssumeRole"])
    error_message = "Without IRSA inputs the role must keep the ECS task trust."
  }
}

run "log_group_prefix_pins_existing_group" {
  command = plan

  variables {
    parameter_prefix = "/fintechbankx"
    log_group_prefix = "/openfinance"
  }

  assert {
    condition     = aws_cloudwatch_log_group.service.name == "/openfinance/dev/loan-lifecycle-service"
    error_message = "log_group_prefix must pin the log group name."
  }

  assert {
    condition     = aws_ssm_parameter.cache_engine.name == "/fintechbankx/dev/loan-lifecycle-service/cache_engine"
    error_message = "SSM parameters must follow parameter_prefix."
  }
}

run "irsa_trusts_exactly_one_service_account" {
  command = plan

  variables {
    eks_oidc_provider_arn      = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
    eks_oidc_provider_url      = "https://oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
    kubernetes_namespace       = "lending"
    kubernetes_service_account = "loan-lifecycle-service"
  }

  assert {
    condition     = one(data.aws_iam_policy_document.workload_assume_role.statement).actions == toset(["sts:AssumeRoleWithWebIdentity"])
    error_message = "IRSA must use web identity."
  }

  assert {
    condition = toset(flatten([
      for c in one(data.aws_iam_policy_document.workload_assume_role.statement).condition : tolist(c.values)
      if c.variable == "oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE:sub"
    ])) == toset(["system:serviceaccount:lending:loan-lifecycle-service"])
    error_message = "IRSA sub must be system:serviceaccount:lending:loan-lifecycle-service."
  }
}

run "irsa_without_namespace_fails" {
  command = plan

  variables {
    eks_oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
    eks_oidc_provider_url = "https://oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  }

  expect_failures = [aws_iam_role.workload]
}
