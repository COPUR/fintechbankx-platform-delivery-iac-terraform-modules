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
    error_message = "The instance role carries only the SSM core policy."
  }
}

run "any_address_egress_rejected" {
  command = plan

  variables {
    egress_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.egress_cidr_blocks]
}
