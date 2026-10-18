# Personal database logins for operators of one service database, through IAM
# database authentication: each person connects as their own login, so
# session_user (and pgaudit) names the login, not a shared role.
#
# AWS side (this module): one customer managed policy for the operators'
# IAM Identity Center permission set. Each statement allows rds-db:connect as
# one login only from a session whose aws:userid ends in that person's
# Identity Center user name (<role id>:<user name>, a session name Identity
# Center sets). The policy only adds an allow: it does not stop other
# principals with a broader rds-db:connect, an identity-source admin who
# renames a user, or the master user (README "Residual risk"). The module
# creates no permission set; the account-baseline owner adds this policy to it
# by name.
#
# Database side (output login_sql): the desired state, run by the DBA as the
# cluster's master user. The group role and the logins are cluster roles,
# which the service's migration user cannot create. What the group may do in
# the service's schema is granted by the service's own migration, never here.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Sorted by login so statement ids and the SQL are stable.
  logins            = sort(values(var.operators))
  user_of           = { for user, login in var.operators : login => user }
  dbuser_arn_prefix = "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.cluster_resource_id}"

  policy = {
    Version = "2012-10-17"
    Statement = [for i, login in local.logins : {
      Sid       = "ConnectAsOperator${i}"
      Effect    = "Allow"
      Action    = "rds-db:connect"
      Resource  = "${local.dbuser_arn_prefix}/${login}"
      Condition = { StringLike = { "aws:userid" = "*:${local.user_of[login]}" } }
    }]
  }

  sql_list = join(", ", [for l in local.logins : "'${l}'"])
  # Identity Center user names in the order of the logins, for the SQL's ownership marks.
  sql_users = join(", ", [for l in local.logins : "'${local.user_of[l]}'"])
  # The group's mark names the instance and its mode, so an instance of the other mode given
  # the same group name stops instead of taking that group's logins over.
  group_mark = "operator-db-login group ${var.environment}/${var.service_slug}${var.read_only ? " read-only" : ""}"

  # IAM counts a customer managed policy's size without whitespace; the limit is 6,144 characters.
  policy_json       = jsonencode(local.policy)
  policy_size       = length(replace(local.policy_json, "/\\s/", ""))
  policy_size_limit = 6144
}

resource "aws_iam_policy" "connect" {
  name        = "${var.environment}-${var.service_slug}-db-${var.read_only ? "readonly" : "operator"}-login"
  description = "IAM database authentication to ${var.database_name}: each ${var.read_only ? "read-only " : ""}operator as their own login only"
  policy      = local.policy_json
  tags        = merge(var.tags, { "fintechbankx.io/service-slug" = var.service_slug })

  lifecycle {
    precondition {
      condition     = !contains(var.reserved_db_users, var.operator_group_role) && length(setintersection(toset(var.reserved_db_users), toset(local.logins))) == 0
      error_message = "operator_group_role and the operator logins must differ from the service's own database users (reserved_db_users)."
    }

    precondition {
      condition     = local.policy_size <= local.policy_size_limit
      error_message = "The connect policy would be ${local.policy_size} characters without whitespace; IAM allows ${local.policy_size_limit} for a customer managed policy. Use fewer operators, or shorter user names and logins."
    }
  }
}
