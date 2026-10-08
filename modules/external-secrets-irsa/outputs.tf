output "role_arn" {
  description = "Service store role: annotate SA external-secrets/external-secrets with this ARN (eks.amazonaws.com/role-arn)."
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

output "platform_secrets_role_arn" {
  description = "Platform store role: annotate SA external-secrets/external-secrets-platform (mesh overlay parameter PLATFORM_SECRETS_ROLE_ARN). null when create_platform_role is false."
  value       = var.create_platform_role ? module.platform_role[0].role_arn : null
}

output "platform_secret_arn_patterns" {
  description = "Secrets the platform store can read (and the service store cannot, except oidc-client)."
  value       = concat(local.platform_only_secret_arns, [local.oidc_client_secret_arn])
}
