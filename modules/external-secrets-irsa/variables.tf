variable "cluster_name" {
  type        = string
  description = "EKS cluster name, used for the default role name."
}

variable "environment" {
  type        = string
  description = "Environment; the role reads secrets named <environment>/*."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS IAM OIDC provider ARN."
}

variable "oidc_provider_url" {
  type        = string
  description = "EKS OIDC issuer URL (with or without https://)."
}

variable "namespace" {
  type        = string
  description = "Namespace of External Secrets Operator."
  default     = "external-secrets"
}

variable "service_account" {
  type        = string
  description = "Service account of External Secrets Operator."
  default     = "external-secrets"
}

variable "role_name" {
  type        = string
  description = "Role name override. null uses <cluster_name>-external-secrets."
  default     = null
}

variable "create_platform_role" {
  type        = bool
  description = "Create the platform-store role (ClusterSecretStore aws-secrets-manager-platform)."
  default     = true
}

variable "platform_service_account" {
  type        = string
  description = "Token-only service account the platform ClusterSecretStore authenticates as."
  default     = "external-secrets-platform"
}

variable "platform_role_name" {
  type        = string
  description = "Platform-store role name override. null uses <cluster_name>-external-secrets-platform."
  default     = null
}

variable "platform_secret_prefixes" {
  type        = list(string)
  description = "Secret prefixes under <env>/ that only the platform store may read (denied to the service store). Matches the identity repo's deploy/terraform secret names."
  default     = ["platform", "identity-keycloak", "identity-openldap"]

  validation {
    condition     = alltrue([for p in var.platform_secret_prefixes : can(regex("^[a-z][a-z0-9-]+$", p))])
    error_message = "platform_secret_prefixes must be plain lowercase names (no wildcards or slashes)."
  }
}

variable "kms_key_tag_key" {
  type        = string
  description = "Tag key that marks KMS keys the operator may decrypt with."
  default     = "fintechbankx.io/secrets"
}

variable "kms_key_tag_value" {
  type        = string
  description = "Tag value that marks KMS keys the operator may decrypt with."
  default     = "true"
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
