output "role_arns" {
  description = "Operator role ARN per service slug."
  value       = { for s, r in aws_iam_role.this : s => r.arn }
}

output "db_import_secret_names" {
  description = "Secret each role may read, per service slug (<env>/<slug>/db-import)."
  value       = { for s in var.service_slugs : s => "${var.environment}/${s}/db-import" }
}

output "db_import_secret_arns" {
  description = "ARN of each created db-import secret container (empty map when create_db_import_secrets is false)."
  value       = { for s, sec in aws_secretsmanager_secret.db_import : s => sec.arn }
}
