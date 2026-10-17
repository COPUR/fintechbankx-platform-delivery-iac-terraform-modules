# Personal database logins for operators of one service database, through IAM
# database authentication: each person connects as their own login, so
# session_user (and pgaudit) names the person, not a shared role.
#
# AWS side (this module): one customer managed policy for the operators'
# IAM Identity Center permission set. Each statement lets one person connect
# as their own login only: aws:userid of a permission-set session is
# <role id>:<Identity Center user name>, a session name Identity Center sets
# and the person cannot choose. The module creates no permission set; the
# account-baseline owner adds this policy to it by name.
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
}

resource "aws_iam_policy" "connect" {
  name        = "${var.environment}-${var.service_slug}-db-operator-login"
  description = "IAM database authentication to ${var.database_name}: each operator as their own login only"
  policy      = jsonencode(local.policy)
  tags        = merge(var.tags, { "fintechbankx.io/service-slug" = var.service_slug })

  lifecycle {
    precondition {
      condition     = !contains(var.reserved_db_users, var.operator_group_role) && length(setintersection(toset(var.reserved_db_users), toset(local.logins))) == 0
      error_message = "operator_group_role and the operator logins must differ from the service's own database users (reserved_db_users)."
    }
  }
}
