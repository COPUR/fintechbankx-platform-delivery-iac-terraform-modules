output "role_arn" {
  description = "Annotate the external-secrets service account with this ARN (eks.amazonaws.com/role-arn)."
  value       = module.role.role_arn
}

output "role_name" {
  description = "Role name."
  value       = module.role.role_name
}

output "secret_arn_pattern" {
  description = "Secrets the operator can read."
  value       = local.secret_arn_pattern
}
