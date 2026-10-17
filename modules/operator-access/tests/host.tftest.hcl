# Offline (mock provider): the operator host is reachable through SSM Session
# Manager only: private subnet, no public IP, no key pair or inbound rule in
# the module,
# IMDSv2 required, encrypted root volume.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0", insecure_value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "me-central-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

override_resource {
  target = aws_kms_key.session_logs
  values = { arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-00000000c0de" }
}

variables {
  name               = "fintechbankx-dev"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_id          = "subnet-0aaaaaaaaaaaaaaa1"
  egress_cidr_blocks = ["10.10.0.0/16"]
}

run "ssm_only_host" {
  command = plan

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "No public IP."
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDSv2 only, hop limit 1."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "Root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0aaaaaaaaaaaaaaa1"
    error_message = "The host runs in the given private subnet."
  }

  assert {
    condition     = toset([for r in aws_vpc_security_group_egress_rule.this : r.from_port]) == toset([443, 5432])
    error_message = "Egress only to HTTPS (SSM endpoints) and PostgreSQL."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.this : r.cidr_ipv4 == "10.10.0.0/16"])
    error_message = "Egress stays inside the VPC CIDR."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The instance role carries the SSM core policy (plus only its own session-log policy)."
  }
}

run "any_address_egress_rejected" {
  command = plan

  variables {
    egress_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.egress_cidr_blocks]
}

# Session Manager logging is the evidence trail of operator sessions: a
# KMS-encrypted CloudWatch log group per environment, writable by the host.
run "session_logs_encrypted_by_default" {
  command = apply

  assert {
    condition     = aws_cloudwatch_log_group.session_logs[0].name == "/aws/ssm/fintechbankx-dev/sessions" && aws_cloudwatch_log_group.session_logs[0].retention_in_days == 365
    error_message = "Session log group /aws/ssm/<name>/sessions, kept 365 days by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.session_logs[0].kms_key_id == aws_kms_key.session_logs[0].arn && aws_kms_key.session_logs[0].enable_key_rotation
    error_message = "Session logs are encrypted with a rotating CMK."
  }

  assert {
    condition     = !contains(keys(aws_kms_key.session_logs[0].tags), "fintechbankx.io/secrets")
    error_message = "The session log key is not a secrets key (External Secrets may not use it)."
  }

  assert {
    condition     = length(aws_iam_role_policy.session_logs) == 1
    error_message = "The host may write its session logs."
  }

  assert {
    condition     = length(aws_ssm_document.session_preferences) == 0
    error_message = "The account-wide Session Manager preferences document is opt-in."
  }

  assert {
    condition     = output.session_log_group_name == "/aws/ssm/fintechbankx-dev/sessions"
    error_message = "The log group name is an output."
  }
}

run "session_preferences_point_at_the_encrypted_group" {
  command = apply

  variables {
    manage_session_manager_preferences = true
  }

  assert {
    condition     = aws_ssm_document.session_preferences[0].name == "SSM-SessionManagerRunShell" && aws_ssm_document.session_preferences[0].document_type == "Session"
    error_message = "Session Manager preferences live in the Session document SSM-SessionManagerRunShell."
  }

  assert {
    condition = (
      jsondecode(aws_ssm_document.session_preferences[0].content).inputs.cloudWatchLogGroupName == "/aws/ssm/fintechbankx-dev/sessions" &&
      jsondecode(aws_ssm_document.session_preferences[0].content).inputs.cloudWatchEncryptionEnabled == true &&
      jsondecode(aws_ssm_document.session_preferences[0].content).inputs.kmsKeyId == "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-00000000c0de"
    )
    error_message = "Preferences stream sessions to the encrypted group and encrypt session data with the CMK."
  }
}
