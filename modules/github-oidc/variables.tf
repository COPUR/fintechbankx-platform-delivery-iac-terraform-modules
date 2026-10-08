variable "environment" {
  type        = string
  description = "Environment of this account (GitHub environment name, sub ...:environment:<env>)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "github_org" {
  type        = string
  description = "GitHub organisation or owner."
  default     = "COPUR"
}

variable "create_oidc_provider" {
  type        = bool
  description = "Create the token.actions.githubusercontent.com provider (once per account)."
  default     = true
}

variable "oidc_provider_arn" {
  type        = string
  description = "Existing GitHub OIDC provider ARN when create_oidc_provider is false."
  default     = null
}

variable "oidc_thumbprints" {
  type        = list(string)
  description = "Thumbprints for the GitHub OIDC provider. AWS validates GitHub tokens against its own trust store; the values are still required by the API."
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

variable "services" {
  type = map(object({
    repository          = string
    image_name          = string
    namespace           = string
    terraform_state_key = string
    # Name prefix of the service's own AWS resources the tf-plan role may
    # describe; null uses <env>-<image_name>.
    resource_name_prefix = optional(string)
  }))
  description = "Service id -> GitHub repository, image name (= Kubernetes service account and service slug), context namespace, Terraform state key (one per service) and optional resource name prefix."
  default     = {}

  validation {
    condition = alltrue([for id, s in var.services :
      can(regex("^svc-[a-z0-9]+-[a-z0-9-]+$", id)) && length(id) <= 42 &&
      can(regex("^[A-Za-z0-9_.-]+$", s.repository)) &&
      can(regex("^[a-z][a-z0-9-]+$", s.image_name)) &&
      can(regex("^[a-z][a-z0-9-]+$", s.namespace)) &&
      can(regex("^[A-Za-z0-9_.:/=+@-]{1,240}$", s.terraform_state_key)) &&
      (s.resource_name_prefix == null || can(regex("^[a-z][a-z0-9-]+$", coalesce(s.resource_name_prefix, "x"))))
    ])
    error_message = "Keys must be service ids of at most 42 characters (role name limit); repository, image_name and namespace must be plain names; state keys must use IAM tag value characters only (no wildcards, at most 240 characters); resource_name_prefix must be lowercase kebab-case."
  }

  validation {
    condition     = length(distinct([for s in values(var.services) : s.terraform_state_key])) == length(var.services)
    error_message = "Each service needs its own terraform_state_key; two services may not share state."
  }
}

variable "create_ecr_push_roles" {
  type        = bool
  description = "Create ECR push roles in this account (the account that holds the ECR repositories)."
  default     = true
}

variable "eks_cluster_name" {
  type        = string
  description = "EKS cluster the deploy roles target."
}

variable "create_eks_access_entries" {
  type        = bool
  description = "Create EKS access entries mapping deploy roles to fintechbankx:deploy:<namespace>."
  default     = true
}

variable "terraform_state_bucket" {
  type        = string
  description = "S3 state bucket of this environment."
}

variable "terraform_lock_table" {
  type        = string
  description = "DynamoDB lock table."
  default     = "fintechbankx-terraform-locks"
}

variable "terraform_state_kms_key_arn" {
  type        = string
  description = "KMS key of the state bucket (null for SSE-S3)."
  default     = null
}

variable "apply_policy_arns" {
  type        = list(string)
  description = "Policies granting what service Terraform creates (Aurora, KMS, Secrets Manager, IAM under a boundary). Kept explicit on purpose; AWS-managed AdministratorAccess, PowerUserAccess, ReadOnlyAccess and ViewOnlyAccess are rejected."
  default     = []

  validation {
    condition     = alltrue([for a in var.apply_policy_arns : !can(regex(":iam::aws:policy/(AdministratorAccess|PowerUserAccess|ReadOnlyAccess|ViewOnlyAccess)$", a))])
    error_message = "apply_policy_arns must not include AdministratorAccess, PowerUserAccess, ReadOnlyAccess or ViewOnlyAccess; grant service-scoped policies."
  }
}

variable "terraform_state_bucket_key_enabled" {
  type        = bool
  description = "Set true if the state bucket uses S3 Bucket Keys: the KMS encryption context is then the bucket ARN instead of the object ARN (per-key scoping relies on the S3 policies alone)."
  default     = false
}

variable "manage_terraform_state_bucket_policy" {
  type        = bool
  description = "Attach terraform_state_bucket_policy_json to the state bucket. This replaces the bucket's whole policy: pass existing statements in terraform_state_bucket_policy_source_json."
  default     = false
}

variable "terraform_state_bucket_policy_source_json" {
  type        = string
  description = "Existing state-bucket policy statements to keep (e.g. TLS-only, deny unencrypted puts); merged before the CI deny statements."
  default     = null
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Permissions boundary for every CI role (recommended for tf-apply)."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
