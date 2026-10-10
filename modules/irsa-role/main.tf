# IAM role that exactly one Kubernetes service account can assume through the
# EKS OIDC provider (IRSA). Trust: system:serviceaccount:<namespace>:<sa>.

locals {
  issuer = trimprefix(var.oidc_provider_url, "https://")
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = [for sa in var.service_accounts : "system:serviceaccount:${sa.namespace}:${sa.name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = var.description
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each   = var.policy_arns
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count  = (var.attach_inline_policy != null ? var.attach_inline_policy : var.inline_policy_json != null) ? 1 : 0
  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
