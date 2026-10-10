# In-VPC operator host reachable through AWS Systems Manager Session Manager
# only (no SSH, no key pair, no public IP, no inbound rule). Used by platform
# operators for database work (for example a db-import into a service
# database) from inside the VPC. Service databases admit it by adding
# operator_security_group_id to their allowed_security_group_ids.

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name}-operator-host"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-operator-host"
  role = aws_iam_role.this.name
  tags = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-operator-host"
  description = "Operator host (SSM Session Manager only): no inbound, egress to VPC HTTPS and PostgreSQL"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-operator-host" })
}

# No ingress rule: Session Manager connects outbound from the host.
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = { for p in setproduct(var.egress_cidr_blocks, var.egress_ports) : "${p[0]}-${p[1]}" => { cidr = p[0], port = p[1] } }

  security_group_id = aws_security_group.this.id
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  description       = "Operator host egress ${each.value.port} inside the VPC"
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.ami.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "${var.name}-operator-host", "fintechbankx.io/access" = "ssm-session-manager-only" })

  lifecycle {
    # A new AMI in the SSM parameter must not replace the host on every plan.
    ignore_changes = [ami]
  }
}

# --- Session Manager logging (evidence trail) -------------------------------
# Shell sessions on the host stream to a CloudWatch log group encrypted with
# a dedicated CMK, and session data is encrypted with the same key. Port
# forwarding sessions carry no shell transcript: their record is the
# CloudTrail StartSession event (with the caller's source identity) plus the
# database's own pgaudit log.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  session_log_group_name = "/aws/ssm/${var.name}/sessions"
  session_log_group_arn  = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.session_log_group_name}"
}

data "aws_iam_policy_document" "session_logs_key" {
  count = var.session_logging_enabled ? 1 : 0

  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogsForTheSessionLogGroup"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.session_log_group_arn]
    }
  }
}

resource "aws_kms_key" "session_logs" {
  count                   = var.session_logging_enabled ? 1 : 0
  description             = "${var.name} Session Manager session logs and session data"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.session_logs_key[0].json
  tags                    = var.tags
}

resource "aws_kms_alias" "session_logs" {
  count         = var.session_logging_enabled ? 1 : 0
  name          = "alias/${var.name}-ssm-sessions"
  target_key_id = aws_kms_key.session_logs[0].key_id
}

resource "aws_cloudwatch_log_group" "session_logs" {
  count             = var.session_logging_enabled ? 1 : 0
  name              = local.session_log_group_name
  retention_in_days = var.session_log_retention_days
  kms_key_id        = aws_kms_key.session_logs[0].arn
  tags              = var.tags
}

# The SSM agent on the host writes the session stream and decrypts the
# session data key.
data "aws_iam_policy_document" "session_logs" {
  count = var.session_logging_enabled ? 1 : 0

  statement {
    sid       = "WriteSessionLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [local.session_log_group_arn, "${local.session_log_group_arn}:*"]
  }

  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.session_logs[0].arn]
  }
}

resource "aws_iam_role_policy" "session_logs" {
  count  = var.session_logging_enabled ? 1 : 0
  name   = "ssm-session-logs"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.session_logs[0].json
}

# Session Manager preferences are one document per account and region
# (SSM-SessionManagerRunShell). Opt-in: another stack or the console may own it.
resource "aws_ssm_document" "session_preferences" {
  count           = var.session_logging_enabled && var.manage_session_manager_preferences ? 1 : 0
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  tags            = var.tags

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences (${var.name}): KMS-encrypted sessions and CloudWatch session logs"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = aws_kms_key.session_logs[0].arn
      cloudWatchLogGroupName      = local.session_log_group_name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      idleSessionTimeout          = tostring(var.session_idle_timeout_minutes)
      runAsEnabled                = false
      runAsDefaultUser            = ""
      shellProfile                = { linux = "", windows = "" }
    }
  })
}
