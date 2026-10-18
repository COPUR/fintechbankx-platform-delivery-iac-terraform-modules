output "policy_arn" {
  description = "Customer managed policy with one rds-db:connect statement per operator."
  value       = aws_iam_policy.connect.arn
}

output "policy_name" {
  description = "Name to add to the operators' Identity Center permission set as a customer managed policy reference (path /)."
  value       = aws_iam_policy.connect.name
}

output "operator_logins" {
  description = "Identity Center user name => database login."
  value       = var.operators
}

output "operator_group_role" {
  description = "Group role the logins belong to; the service's migration grants it the operator privileges."
  value       = var.operator_group_role
}

output "login_sql" {
  description = "Desired-state SQL for the DBA: run as the cluster's master user in database_name with psql -v ON_ERROR_STOP=1 --single-transaction -f. Holds no secret."
  value = templatefile("${path.module}/login.sql.tftpl", {
    environment      = var.environment
    service_slug     = var.service_slug
    database_name    = var.database_name
    group            = var.operator_group_role
    logins           = local.sql_list
    reserved         = join(", ", [for u in sort(var.reserved_db_users) : "'${u}'"])
    connection_limit = var.connection_limit
    idle_tx_seconds  = var.idle_in_transaction_timeout_seconds
    read_only        = var.read_only
  })
}
