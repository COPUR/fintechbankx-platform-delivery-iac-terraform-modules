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
