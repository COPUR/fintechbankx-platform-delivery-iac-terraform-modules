variable "role_name" {
  type        = string
  description = "IAM role name, e.g. <env>-<service-slug>-irsa."

  validation {
    condition     = length(var.role_name) <= 64 && can(regex("^[A-Za-z0-9+=,.@_-]+$", var.role_name))
    error_message = "role_name must be a valid IAM role name of at most 64 characters."
  }
}

variable "description" {
  type        = string
  description = "Role description."
  default     = "IRSA role managed by fintechbankx terraform-modules"
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS IAM OIDC provider ARN (eks-cluster output oidc_provider_arn)."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN."
  }
}

variable "oidc_provider_url" {
  type        = string
  description = "EKS OIDC issuer URL, with or without https:// (eks-cluster output oidc_provider_url)."
}

variable "service_accounts" {
  type = list(object({
    namespace = string
    name      = string
  }))
  description = "Service accounts allowed to assume the role. Normally exactly one."

  validation {
    condition     = length(var.service_accounts) >= 1 && alltrue([for sa in var.service_accounts : sa.namespace != "*" && sa.name != "*"])
    error_message = "List at least one service account; wildcards are not allowed."
  }
}

variable "policy_arns" {
  type        = map(string)
  description = "Managed policies to attach, keyed by a stable name (e.g. { runtime = module.service_base.runtime_access_policy_arn })."
  default     = {}
}

variable "inline_policy_json" {
  type        = string
  description = "Optional inline policy document."
  default     = null
}

variable "max_session_duration" {
  type        = number
  description = "Maximum session duration in seconds."
  default     = 3600
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Optional permissions boundary."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
