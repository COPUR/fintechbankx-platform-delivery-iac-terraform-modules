output "role_arns" {
  description = "Operator role ARN per service slug."
  value       = { for s, r in aws_iam_role.this : s => r.arn }
}

output "db_import_secret_names" {
  description = "Secret each role may read, per service slug (<env>/<slug>/db-import)."
  value       = { for s in var.service_slugs : s => "${var.environment}/${s}/db-import" }
}
