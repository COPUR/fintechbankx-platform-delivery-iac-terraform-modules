# Offline (mock providers, no credentials): operator access wiring.
# Session Manager on the private operator host needs the ssmmessages and
# ec2messages interface endpoints (and kms for session encryption and the
# secrets key); the db-import secrets use each service's ADR-023 secrets key.
# The state-bucket policy check is turned off here (it reads the live bucket
# policy; covered in modules/github-oidc/tests).

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
  environment                          = "dev"
  vpc_cidr                             = "10.40.0.0/16"
  verify_terraform_state_bucket_policy = false
  github_services                      = {}
}

run "operator_endpoints_off_by_default" {
  command = plan

  assert {
    condition     = length(setintersection(toset(module.network.interface_endpoint_services), toset(["ssmmessages", "ec2messages", "kms"]))) == 0
    error_message = "Without operator access the stack adds no Session Manager or KMS endpoints."
  }

  assert {
    condition     = contains(module.network.interface_endpoint_services, "ssm") && contains(module.network.interface_endpoint_services, "secretsmanager")
    error_message = "The default endpoints stay."
  }
}

run "operator_access_adds_session_manager_and_kms_endpoints" {
  command = plan

  variables {
    operator_access_enabled          = true
    operator_db_import_service_slugs = ["payment-request-to-pay-service"]
    operator_principal_arns          = ["arn:aws:iam::111122223333:role/aws-reserved/sso.amazonaws.com/me-central-1/AWSReservedSSO_DbOperator_0123456789abcdef"]
    operator_db_import_kms_key_arns = {
      "payment-request-to-pay-service" = "arn:aws:kms:me-central-1:111122223333:key/11111111-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = length(setintersection(toset(module.network.interface_endpoint_services), toset(["ssm", "ssmmessages", "ec2messages", "kms", "secretsmanager", "sts", "logs"]))) == 7
    error_message = "Session Manager on the private host needs ssm, ssmmessages and ec2messages; kms, secretsmanager, sts and logs serve the credential path and session logs."
  }

  assert {
    condition     = module.operator_db_access[0].kms_key_arns == { "payment-request-to-pay-service" = "arn:aws:kms:me-central-1:111122223333:key/11111111-2222-3333-4444-555555555555" }
    error_message = "db-import secrets use the secrets key passed in operator_db_import_kms_key_arns."
  }

  assert {
    condition     = module.operator_access[0].session_log_group_name == "/aws/ssm/fintechbankx-dev/sessions"
    error_message = "Session Manager logging is on with the operator host."
  }
}
