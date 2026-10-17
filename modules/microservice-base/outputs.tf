output "service_info" {
  description = "Service name, slug and environment."
  value = {
    name        = var.service_name
    slug        = var.service_slug
    environment = var.environment
  }
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name."
  value       = aws_cloudwatch_log_group.service.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN."
  value       = aws_cloudwatch_log_group.service.arn
}

output "workload_role_arn" {
  description = "Workload IAM role ARN (ECS task role or IRSA role)."
  value       = aws_iam_role.workload.arn
}

output "workload_role_name" {
  description = "Workload IAM role name."
  value       = aws_iam_role.workload.name
}

output "secret_arn" {
  description = "Runtime bootstrap secret ARN."
  value       = aws_secretsmanager_secret.service_runtime.arn
}

output "secret_name" {
  description = "Runtime bootstrap secret name (<env>/<slug>/runtime)."
  value       = aws_secretsmanager_secret.service_runtime.name
}

output "runtime_access_policy_arn" {
  description = "Managed policy granting read of this service's SSM path and runtime secret; attach it to your own IRSA role."
  value       = aws_iam_policy.runtime_access.arn
}

output "ssm_parameter_root" {
  description = "SSM path root <parameter_prefix>/<env>/<slug>."
  value       = local.parameter_root
}

output "ssm_parameter_paths" {
  description = "Names of the SSM parameters written by the module."
  value = {
    database_engine       = aws_ssm_parameter.database_engine.name
    cache_engine          = aws_ssm_parameter.cache_engine.name
    identity_provider_url = aws_ssm_parameter.identity_provider_url.name
    observability         = aws_ssm_parameter.observability_endpoint.name
  }
}
