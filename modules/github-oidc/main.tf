# GitHub Actions OIDC federation for one AWS account / environment, matching
# fintechbankx-platform-delivery-iac-cicd-templates
# (docs/delivery/CONSUMING_DELIVERY_WORKFLOWS.md section 4). Per service:
#  - ecr-push  : sub repo:<org>/<repo>:ref:refs/heads/main; push/pull on
#                fintechbankx/<image_name> only
#  - deploy    : sub repo:<org>/<repo>:environment:<env>; eks:DescribeCluster,
#                pull of fintechbankx/<image_name> (cosign verify)
#                plus an EKS access entry in Kubernetes group
#                fintechbankx:deploy:<namespace> (bind that group to a
#                namespaced Role with a RoleBinding; never cluster-admin)
#  - tf-plan   : sub pull_request or ref:refs/heads/main; read-only metadata
#                access scoped to the service's own resources (name prefix
#                <env>-<image_name>, secrets <env>/<image_name>/*), plus read
#                of its own state key and its own lock item. No AWS-managed
#                policies: a pull request must never read another service's
#                state, secrets or logs.
#  - tf-apply  : sub environment:<env> only; state read/write on the
#                service's key plus caller-provided policies
# tf-plan/tf-apply roles carry the tag TerraformStateKey; the state bucket
# policy (output terraform_state_bucket_policy_json) denies them every other
# key. No long-lived access keys are created.

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

  # Reusable workflow each CI role kind may run as (bind_platform_workflow_ref).
  platform_workflow = {
    "ecr-push" = "container-image.yml"
    "deploy"   = "helm-deploy.yml"
    "tf-plan"  = "terraform.yml"
    "tf-apply" = "terraform.yml"
  }

  # Allowed sub values per role. With the binding on, each subject gets the
  # job_workflow_ref suffix GitHub appends when the repository's sub template
  # includes it: <subject>:job_workflow_ref:<org>/<repo>/.github/workflows/<file>@<ref>.
  trusted_sub_values = {
    for k, v in local.role_sets : k => var.bind_platform_workflow_ref ? flatten([
      for s in local.trusted_subjects[v.kind] : [
        for ref in var.platform_workflow_refs :
        "${local.subjects[v.id][s]}:job_workflow_ref:${var.github_org}/${var.platform_workflows_repository}/.github/workflows/${local.platform_workflow[v.kind]}@${ref}"
      ]
    ]) : [for s in local.trusted_subjects[v.kind] : local.subjects[v.id][s]]
  }

  trusted_subjects = {
    "ecr-push" = ["main"]
    "deploy"   = ["environment"]
    "tf-plan"  = ["pr", "main"]
    "tf-apply" = ["environment"]
  }

  state_bucket_arn = "arn:${local.partition}:s3:::${var.terraform_state_bucket}"
  lock_table_arn   = "arn:${local.partition}:dynamodb:${local.region}:${local.account_id}:table/${var.terraform_lock_table}"

  # Resource name prefix of the service's own Terraform stack
  # (<env>-<image_name>, as aurora-postgresql, documentdb-cluster,
  # elasticache-redis and microservice-base name their resources).
  service_prefix = { for id, s in var.services : id => coalesce(s.resource_name_prefix, "${var.environment}-${s.image_name}") }

  ci_terraform_role_arn_patterns = [
    "arn:${local.partition}:iam::${local.account_id}:role/gha-${var.environment}-*-tf-plan",
    "arn:${local.partition}:iam::${local.account_id}:role/gha-${var.environment}-*-tf-apply",
  ]

  # Every managed policy attachment in this module (only tf-apply roles get any).
  managed_policy_attachments = {
    for pair in flatten([
      for k, v in local.role_sets : [
        for i, arn in var.apply_policy_arns : { key = "${k}/${i}", role_key = k, policy_arn = arn }
      ] if v.kind == "tf-apply"
    ]) : pair.key => pair
  }
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
      # StringLike only for tag patterns such as refs/tags/v*.
      test     = var.bind_platform_workflow_ref ? "StringLike" : "StringEquals"
      variable = "${local.issuer}:sub"
      values   = local.trusted_sub_values[each.key]
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
  tags = merge(local.tags, { Service = each.value.id, CiRole = each.value.kind },
    contains(["tf-plan", "tf-apply"], each.value.kind) ? { TerraformStateKey = var.services[each.value.id].terraform_state_key } : {}
  )

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
  for_each = { for k, v in local.role_sets : k => v if v.kind == "deploy" }

  statement {
    sid       = "DescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.eks_cluster_name}"]
  }

  # cosign verify before helm upgrade: pull the service's own image manifest
  # and its signature (same repository); no push.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PullOwnImageAndSignature"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = ["arn:${local.partition}:ecr:${local.region}:${coalesce(var.ecr_registry_account_id, local.account_id)}:repository/fintechbankx/${var.services[each.value.id].image_name}"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  for_each = data.aws_iam_policy_document.deploy
  name     = "eks-describe"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.json
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
    sid       = "ListOwnStateKey"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringEquals"
      variable = "s3:prefix"
      values = each.value.kind == "tf-apply" ? [
        var.services[each.value.id].terraform_state_key,
        "${var.services[each.value.id].terraform_state_key}.tflock",
      ] : [var.services[each.value.id].terraform_state_key]
    }
  }

  statement {
    sid       = "StateObject"
    actions   = each.value.kind == "tf-apply" ? ["s3:GetObject", "s3:PutObject"] : ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/${var.services[each.value.id].terraform_state_key}"]
  }

  statement {
    sid       = "StateLockTable"
    actions   = ["dynamodb:DescribeTable"]
    resources = [local.lock_table_arn]
  }

  # Lock item <bucket>/<key> and digest item <bucket>/<key>-md5, exact keys.
  statement {
    sid       = "StateLockRead"
    actions   = ["dynamodb:GetItem"]
    resources = [local.lock_table_arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "dynamodb:LeadingKeys"
      values = [
        "${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}",
        "${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}-md5",
      ]
    }
  }

  # Plan only takes and releases the lock; only apply writes the digest.
  statement {
    sid       = "StateLockWrite"
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [local.lock_table_arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "dynamodb:LeadingKeys"
      values = each.value.kind == "tf-apply" ? [
        "${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}",
        "${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}-md5",
      ] : ["${var.terraform_state_bucket}/${var.services[each.value.id].terraform_state_key}"]
    }
  }

  dynamic "statement" {
    for_each = var.terraform_state_kms_key_arn == null ? [] : [1]
    content {
      sid       = "StateEncryption"
      actions   = each.value.kind == "tf-apply" ? ["kms:Decrypt", "kms:GenerateDataKey"] : ["kms:Decrypt"]
      resources = [var.terraform_state_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = [var.terraform_state_bucket_key_enabled ? local.state_bucket_arn : "${local.state_bucket_arn}/${var.services[each.value.id].terraform_state_key}"]
      }
    }
  }
}

resource "aws_iam_role_policy" "state" {
  for_each = data.aws_iam_policy_document.state
  name     = "terraform-state"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.json
}

# Read-only metadata the plan of the service's own stack needs (refresh of
# Aurora/DocumentDB, ElastiCache, KMS, security groups, Secrets Manager, IAM,
# log groups, SSM parameters and alarms created with the module library).
# Resource-scoped to the service's name prefix wherever the API supports it;
# the "*" statement holds only Describe/List calls AWS does not scope. No log
# events, no object reads, no other service's secrets.
data "aws_iam_policy_document" "plan_read" {
  for_each = { for k, v in local.role_sets : k => v if v.kind == "tf-plan" }

  statement {
    sid = "DescribeUnscopedMetadata"
    actions = [
      "cloudwatch:DescribeAlarms",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "elasticache:DescribeCacheEngineVersions",
      "kms:ListAliases",
      "logs:DescribeLogGroups",
      "rds:DescribeDBEngineVersions",
      "rds:DescribeOrderableDBInstanceOptions",
      "ssm:DescribeParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid = "OwnDatabases"
    actions = [
      "rds:DescribeDBClusterParameterGroups",
      "rds:DescribeDBClusterParameters",
      "rds:DescribeDBClusters",
      "rds:DescribeDBInstances",
      "rds:DescribeDBParameterGroups",
      "rds:DescribeDBParameters",
      "rds:DescribeDBSubnetGroups",
      "rds:ListTagsForResource",
    ]
    resources = [for t in ["cluster", "db", "subgrp", "cluster-pg", "pg"] :
      "arn:${local.partition}:rds:${local.region}:${local.account_id}:${t}:${local.service_prefix[each.value.id]}-*"
    ]
  }

  statement {
    sid = "OwnCaches"
    actions = [
      "elasticache:DescribeCacheClusters",
      "elasticache:DescribeCacheParameterGroups",
      "elasticache:DescribeCacheParameters",
      "elasticache:DescribeCacheSubnetGroups",
      "elasticache:DescribeReplicationGroups",
      "elasticache:ListTagsForResource",
    ]
    resources = [for t in ["replicationgroup", "cluster", "subnetgroup", "parametergroup"] :
      "arn:${local.partition}:elasticache:${local.region}:${local.account_id}:${t}:${local.service_prefix[each.value.id]}-*"
    ]
  }

  statement {
    sid       = "OwnKmsKeys"
    actions   = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags"]
    resources = ["arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"]
    condition {
      test     = "ForAnyValue:StringLike"
      variable = "kms:ResourceAliases"
      values   = ["alias/${local.service_prefix[each.value.id]}-*"]
    }
  }

  statement {
    sid = "OwnSecrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = [
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.environment}/${var.services[each.value.id].image_name}/*",
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.service_prefix[each.value.id]}/*",
    ]
  }

  # Refreshing aws_secretsmanager_secret_version reads the value. Only secrets
  # whose value Terraform itself wrote (and so already holds in state) carry
  # fintechbankx.io/value-in-state=true. Operator-filled secrets (db-app,
  # db-migration, oidc-client) are never readable from a pull request.
  statement {
    sid     = "OwnTerraformWrittenSecretValues"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.environment}/${var.services[each.value.id].image_name}/*",
      "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.service_prefix[each.value.id]}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/fintechbankx.io/value-in-state"
      values   = ["true"]
    }
  }

  # GetSecretValue on a secret encrypted with a customer managed key
  # (documentdb-cluster, elasticache-redis, microservice-base kms_key_arn)
  # also needs kms:Decrypt. Only through Secrets Manager and only with the
  # service's own secret ARN in the encryption context, so this grants nothing
  # beyond the tag-scoped GetSecretValue above. Not every service key has an
  # alias (elasticache-redis creates none; microservice-base takes the
  # caller's key), so no kms:ResourceAliases condition.
  statement {
    sid       = "DecryptOwnSecretsViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = ["arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:SecretARN"
      values = [
        "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${var.environment}/${var.services[each.value.id].image_name}/*",
        "arn:${local.partition}:secretsmanager:${local.region}:${local.account_id}:secret:${local.service_prefix[each.value.id]}/*",
      ]
    }
  }

  statement {
    sid = "OwnIamRolesAndPolicies"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListPolicyTags",
      "iam:ListPolicyVersions",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${local.service_prefix[each.value.id]}-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${local.service_prefix[each.value.id]}-*",
    ]
  }

  statement {
    sid       = "ClusterOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider", "eks:DescribeCluster"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/*", "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.eks_cluster_name}"]
  }

  statement {
    sid     = "OwnLogGroupTags"
    actions = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"]
    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/*/${var.environment}/${var.services[each.value.id].image_name}",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/*/${var.environment}/${var.services[each.value.id].image_name}:*",
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/elasticache/${local.service_prefix[each.value.id]}/*",
    ]
  }

  statement {
    sid       = "OwnParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/*/${var.environment}/${var.services[each.value.id].image_name}/*"]
  }

  statement {
    sid       = "OwnAlarmTags"
    actions   = ["cloudwatch:ListTagsForResource"]
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:${local.service_prefix[each.value.id]}-*"]
  }
}

resource "aws_iam_role_policy" "plan_read" {
  for_each = data.aws_iam_policy_document.plan_read
  name     = "plan-read-own-resources"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.json
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each   = local.managed_policy_attachments
  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

# --- State bucket policy ------------------------------------------------------
# Constant-size deny (does not grow with the number of services): a CI
# Terraform role of this environment may touch only the object named by its
# own TerraformStateKey tag (and <key>.tflock), may list only that key, and is
# denied entirely if the tag is missing. Attach it to the state bucket here
# (manage_terraform_state_bucket_policy) or merge the output into the policy
# of whoever owns the bucket.

data "aws_iam_policy_document" "state_bucket" {
  source_policy_documents = var.terraform_state_bucket_policy_source_json == null ? [] : [var.terraform_state_bucket_policy_source_json]

  statement {
    sid       = "DenyCiTerraformRolesWithoutStateKeyTag"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.ci_terraform_role_arn_patterns
    }
    condition {
      test     = "Null"
      variable = "aws:PrincipalTag/TerraformStateKey"
      values   = ["true"]
    }
  }

  statement {
    sid     = "DenyCiTerraformRolesOtherStateObjects"
    effect  = "Deny"
    actions = ["s3:*"]
    not_resources = [
      local.state_bucket_arn,
      "${local.state_bucket_arn}/$${aws:PrincipalTag/TerraformStateKey}",
      "${local.state_bucket_arn}/$${aws:PrincipalTag/TerraformStateKey}.tflock",
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.ci_terraform_role_arn_patterns
    }
  }

  statement {
    sid         = "DenyCiTerraformRolesBucketActionsExceptList"
    effect      = "Deny"
    not_actions = ["s3:ListBucket"]
    resources   = [local.state_bucket_arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.ci_terraform_role_arn_patterns
    }
  }

  statement {
    sid       = "DenyCiTerraformRolesListOutsideOwnKey"
    effect    = "Deny"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = local.ci_terraform_role_arn_patterns
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:prefix"
      values   = ["$${aws:PrincipalTag/TerraformStateKey}", "$${aws:PrincipalTag/TerraformStateKey}.tflock"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  count  = var.manage_terraform_state_bucket_policy ? 1 : 0
  bucket = var.terraform_state_bucket
  policy = data.aws_iam_policy_document.state_bucket.json
}

# Bucket owned elsewhere (bootstrap): prove at plan time that the CI deny
# statements were merged. Without DenyCiTerraformRolesOtherStateObjects every
# CI Terraform role could read every service's state. A bucket with no policy
# at all fails earlier, in the provider read (NoSuchBucketPolicy).
locals {
  ci_state_bucket_deny_sids = [
    "DenyCiTerraformRolesWithoutStateKeyTag",
    "DenyCiTerraformRolesOtherStateObjects",
    "DenyCiTerraformRolesBucketActionsExceptList",
    "DenyCiTerraformRolesListOutsideOwnKey",
  ]
}

data "aws_s3_bucket_policy" "state" {
  count  = var.verify_terraform_state_bucket_policy && !var.manage_terraform_state_bucket_policy ? 1 : 0
  bucket = var.terraform_state_bucket

  lifecycle {
    postcondition {
      condition = length(setsubtract(local.ci_state_bucket_deny_sids, [
        for s in try(flatten([jsondecode(self.policy).Statement]), []) : try(s.Sid, "") if try(s.Effect, "") == "Deny"
      ])) == 0
      error_message = "State bucket ${var.terraform_state_bucket} policy lacks Deny statement(s) ${join(", ", setsubtract(local.ci_state_bucket_deny_sids, [for s in try(flatten([jsondecode(self.policy).Statement]), []) : try(s.Sid, "") if try(s.Effect, "") == "Deny"]))}: merge output terraform_state_bucket_policy_json into the bucket policy (or set manage_terraform_state_bucket_policy)."
    }
  }
}
