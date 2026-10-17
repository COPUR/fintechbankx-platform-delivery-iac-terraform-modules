variable "service_name" {
  type        = string
  description = "Human-readable service name (used in descriptions)."
}

variable "service_slug" {
  type        = string
  description = "Kebab-case service slug, usually the Kubernetes service account name (e.g. loan-lifecycle-service)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.service_slug))
    error_message = "service_slug must be lowercase kebab-case."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "environment must be a short lowercase identifier such as dev, staging or prod."
  }
}

variable "database_engine" {
  type        = string
  description = "Database engine pointer written to SSM (aurora-postgresql, none, ...)."
}

variable "cache_engine" {
  type        = string
  description = "Cache engine pointer written to SSM (redis, none, ...)."
}

variable "identity_provider_url" {
  type        = string
  description = "OIDC issuer URL (Keycloak realm fintechbankx)."
}

variable "observability_endpoint" {
  type        = string
  description = "OTLP or metrics endpoint written to SSM."
}

variable "parameter_prefix" {
  type        = string
  description = "Base SSM parameter path prefix. New services use /fintechbankx; the default keeps the historic /openfinance path."
  default     = "/openfinance"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.parameter_prefix))
    error_message = "parameter_prefix must start with / and must not end with /."
  }
}

variable "log_group_prefix" {
  type        = string
  description = "CloudWatch log group prefix. null (default) follows parameter_prefix. Set it to pin an existing log group name."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention in days."
  default     = 30
}

variable "log_group_kms_key_arn" {
  type        = string
  description = "Optional KMS key for the log group. The key policy must allow logs.<region>.amazonaws.com."
  default     = null
}

variable "kms_key_arn" {
  type        = string
  description = "Optional customer-managed KMS key for the runtime secret. null uses the aws/secretsmanager key."
  default     = null
}

variable "runtime_secret_name" {
  type        = string
  description = "Runtime secret name. null (default) uses the contract name <env>/<slug>/runtime, which the aws-secrets-manager ClusterSecretStore (reads <env>/*) can sync. Set <env>-<slug>/runtime to keep a secret created before 2026-10-08."
  default     = null
}

variable "secret_recovery_window_in_days" {
  type        = number
  description = "Secrets Manager recovery window for the runtime secret."
  default     = 7

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "workload_principal" {
  type        = string
  description = "AWS service principal allowed to assume the workload role when IRSA is not used."
  default     = "ecs-tasks.amazonaws.com"
}

variable "eks_oidc_provider_arn" {
  type        = string
  description = "EKS IAM OIDC provider ARN. When set, the workload role trusts the Kubernetes service account (IRSA) instead of workload_principal."
  default     = null
}

variable "eks_oidc_provider_url" {
  type        = string
  description = "EKS OIDC issuer URL (with or without https://). Required with eks_oidc_provider_arn."
  default     = null
}

variable "kubernetes_namespace" {
  type        = string
  description = "Namespace of the service account (IRSA)."
  default     = null
}

variable "kubernetes_service_account" {
  type        = string
  description = "Service account name (IRSA)."
  default     = null
}

variable "attach_runtime_access_policy" {
  type        = bool
  description = "Attach the runtime access policy to the workload role created here."
  default     = true
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Optional IAM permissions boundary for the workload role."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional resource tags."
  default     = {}
}
