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
