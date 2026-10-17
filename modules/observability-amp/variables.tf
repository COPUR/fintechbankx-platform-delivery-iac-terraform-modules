variable "name" {
  type        = string
  description = "Workspace alias/name, e.g. fintechbankx-prod."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,49}$", var.name))
    error_message = "name must be alphanumeric with dashes, at most 50 characters."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Optional customer-managed KMS key for the AMP workspace. null uses an AWS-owned key. Changing it replaces the workspace."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Retention for AMP workspace logs."
  default     = 30
}

variable "alertmanager_definition" {
  type        = string
  description = "Optional Alertmanager YAML (alertmanager_config: ...)."
  default     = null
}

variable "rule_group_namespaces" {
  type        = map(string)
  description = "Prometheus rule files (YAML) keyed by namespace name, e.g. from the observability repo."
  default     = {}
}

variable "enable_grafana" {
  type        = bool
  description = "Create an Amazon Managed Grafana workspace (check regional availability first)."
  default     = false
}

variable "grafana_authentication_providers" {
  type        = list(string)
  description = "Grafana authentication providers (AWS_SSO or SAML)."
  default     = ["AWS_SSO"]

  validation {
    condition     = alltrue([for p in var.grafana_authentication_providers : contains(["AWS_SSO", "SAML"], p)])
    error_message = "Providers must be AWS_SSO or SAML."
  }
}

variable "grafana_version" {
  type        = string
  description = "Managed Grafana version."
  default     = "10.4"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
