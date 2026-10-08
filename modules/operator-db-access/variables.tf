variable "environment" {
  type        = string
  description = "Environment segment of the secret names (dev, staging, prod)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "service_slugs" {
  type        = list(string)
  description = "Service slugs (Helm chart / service account name, e.g. payment-request-to-pay-service); one role each."

  validation {
    condition     = alltrue([for s in var.service_slugs : can(regex("^[a-z][a-z0-9-]{1,40}$", s))])
    error_message = "service_slugs must be lowercase kebab-case slugs."
  }
}

variable "trusted_principal_arns" {
  type        = list(string)
  description = "IAM role ARNs allowed to assume the operator roles (IAM Identity Center permission-set roles). No wildcard, no account root."

  validation {
    condition     = length(var.trusted_principal_arns) > 0 && alltrue([for a in var.trusted_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", a)) && !strcontains(a, "*")])
    error_message = "trusted_principal_arns must list IAM role ARNs without wildcards."
  }
}

variable "kms_key_arns" {
  type        = map(string)
  description = "Optional CMK ARN per service slug that encrypts its secrets (a secrets-only key, not the database storage key). Used for the db-import secret and to scope kms:Decrypt; without one the secret uses the AWS managed key and the statement is limited by kms:ViaService and the SecretARN encryption context only."
  default     = {}
}

variable "max_session_duration_seconds" {
  type        = number
  description = "Maximum session duration of the operator roles."
  default     = 3600

  validation {
    condition     = var.max_session_duration_seconds >= 900 && var.max_session_duration_seconds <= 14400
    error_message = "max_session_duration_seconds must be 900..14400."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Optional permissions boundary for the roles."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}

variable "create_db_import_secrets" {
  type        = bool
  description = "Create the empty secret container <env>/<slug>/db-import per service (no value: operators fill it with put-secret-value, so it never reaches Terraform state). Set false when another stack owns the secrets."
  default     = true
}

variable "recovery_window_in_days" {
  type        = number
  description = "Recovery window of the db-import secrets."
  default     = 30
}

variable "postgresql_log_group_arns" {
  type        = map(string)
  description = "Optional CloudWatch log group ARN per service slug (the aurora-postgresql log group, e.g. postgresql_log_group_arn). The operator role may then read that group (pgaudit and DDL audit lines) and nothing else in CloudWatch Logs."
  default     = {}

  validation {
    condition     = alltrue([for k, a in var.postgresql_log_group_arns : can(regex("^arn:aws[a-z-]*:logs:[a-z0-9-]+:[0-9]{12}:log-group:[A-Za-z0-9_./#-]+(:\\*)?$", a))])
    error_message = "postgresql_log_group_arns values must be CloudWatch log group ARNs without wildcards in the name."
  }
}
