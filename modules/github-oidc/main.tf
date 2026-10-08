# GitHub Actions OIDC federation for one AWS account / environment, matching
# fintechbankx-platform-delivery-iac-cicd-templates
# (docs/delivery/CONSUMING_DELIVERY_WORKFLOWS.md section 4). Per service:
#  - ecr-push  : sub repo:<org>/<repo>:ref:refs/heads/main; push/pull on
#                fintechbankx/<image_name> only
#  - deploy    : sub repo:<org>/<repo>:environment:<env>; eks:DescribeCluster
#                plus an EKS access entry in Kubernetes group
#                fintechbankx:deploy:<namespace> (bind that group to a
#                namespaced Role with a RoleBinding; never cluster-admin)
#  - tf-plan   : sub pull_request or ref:refs/heads/main; ReadOnlyAccess plus
#                state read and lock on the service's own state key
#  - tf-apply  : sub environment:<env> only; state read/write on the
#                service's key plus caller-provided policies
# No long-lived access keys are created.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  issuer     = "token.actions.githubusercontent.com"

  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.oidc_provider_arn

  tags = merge({ ManagedBy = "terraform", Module = "github-oidc", Environment = var.environment }, var.tags)

  subjects = {
    for id, s in var.services : id => {
      main        = "repo:${var.github_org}/${s.repository}:ref:refs/heads/main"
      pr          = "repo:${var.github_org}/${s.repository}:pull_request"
      environment = "repo:${var.github_org}/${s.repository}:environment:${var.environment}"
    }
  }

  # gha-<env>-<service id without svc->-<kind>; the longest possible name is
  # gha-staging-<38 chars>-ecr-push = 59 characters (IAM limit 64).
  role_names = { for k, v in local.role_sets : k => "gha-${var.environment}-${trimprefix(v.id, "svc-")}-${v.kind}" }

  role_sets = {
    for pair in flatten([
      for id, s in var.services : [
        for kind in compact([
          var.create_ecr_push_roles ? "ecr-push" : "",
          "deploy",
          "tf-plan",
          "tf-apply",
        ]) : { key = "${id}/${kind}", id = id, kind = kind }
      ]
    ]) : pair.key => pair
  }

  trusted_subjects = {
    "ecr-push" = ["main"]
    "deploy"   = ["environment"]
    "tf-plan"  = ["pr", "main"]
    "tf-apply" = ["environment"]
  }

  state_bucket_arn = "arn:${local.partition}:s3:::${var.terraform_state_bucket}"
  lock_table_arn   = "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.terraform_lock_table}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_oidc_provider ? 1 : 0
  url             = "https://${local.issuer}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprints
  tags            = local.tags
}

data "aws_iam_policy_document" "trust" {
  for_each = local.role_sets

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer}:sub"
      values   = [for s in local.trusted_subjects[each.value.kind] : local.subjects[each.value.id][s]]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each             = local.role_sets
  name                 = local.role_names[each.key]
  description          = "GitHub Actions ${each.value.kind} for ${each.value.id} (${var.environment})"
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn
  tags                 = merge(local.tags, { Service = each.value.id, CiRole = each.value.kind })

  lifecycle {
    precondition {
      condition     = length(local.role_names[each.key]) <= 64
      error_message = "IAM role name exceeds 64 characters; shorten the service id."
    }
  }
}

# --- ECR push ---------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  for_each = { for k, v in local.role_sets : k => v if v.kind == "ecr-push" }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushPullOwnRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/fintechbankx/${var.services[each.value.id].image_name}"]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = data.aws_iam_policy_document.ecr_push
  name     = "ecr-push"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.json
}

# --- EKS deploy ---------------------------------------------------------------

data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.eks_cluster_name}"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = { for k, v in local.role_sets : k => v if v.kind == "deploy" }
  name     = "eks-describe"
  role     = aws_iam_role.this[each.key].id
  policy   = data.aws_iam_policy_document.deploy.json
}

resource "aws_eks_access_entry" "deploy" {
  for_each          = var.create_eks_access_entries ? { for k, v in local.role_sets : k => v if v.kind == "deploy" } : {}
  cluster_name      = var.eks_cluster_name
  principal_arn     = aws_iam_role.this[each.key].arn
  type              = "STANDARD"
  kubernetes_groups = ["fintechbankx:deploy:${var.services[each.value.id].namespace}"]
  tags              = local.tags
}

# --- Terraform plan / apply ---------------------------------------------------

data "aws_iam_policy_document" "state" {
  for_each = { for k, v in local.role_sets : k => v if contains(["tf-plan", "tf-apply"], v.kind) }

  statement {
    sid       = "ListOwnStatePrefix"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.services[each.value.id].terraform_state_key, "${var.services[each.value.id].terraform_state_key}.tflock"]
    }
  }

  statement {
    sid       = "StateObject"
    actions   = each.value.kind == "tf-apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/${var.services[each.value.id].terraform_state_key}"]
  }

  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [local.lock_table_arn]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}*"]
    }
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn == null ? [] : [1]
    content {
      sid       = "StateEncryption"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      resources = [var.terraform_state_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "state" {
  for_each = data.aws_iam_policy_document.state
  name     = "terraform-state"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  for_each   = { for k, v in local.role_sets : k => v if v.kind == "tf-plan" }
  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = {
    for pair in flatten([
      for k, v in local.role_sets : [
        for i, arn in var.apply_policy_arns : { key = "${k}/${i}", role = k, arn = arn }
      ] if v.kind == "tf-apply"
    ]) : pair.key => pair
  }
  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}
