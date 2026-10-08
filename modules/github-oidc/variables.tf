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
  }))
  description = "Service id -> GitHub repository, image name (= Kubernetes service account), context namespace and Terraform state key."
  default     = {}

  validation {
    condition = alltrue([for id, s in var.services :
      can(regex("^svc-[a-z0-9]+-[a-z0-9-]+$", id)) && length(id) <= 42 &&
      can(regex("^[A-Za-z0-9_.-]+$", s.repository)) &&
      can(regex("^[a-z][a-z0-9-]+$", s.image_name)) &&
      can(regex("^[a-z][a-z0-9-]+$", s.namespace)) &&
      !strcontains(s.terraform_state_key, "*")
    ])
    error_message = "Keys must be service ids of at most 42 characters (role name limit); repository, image_name and namespace must be plain names; state keys must not contain wildcards."
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
  description = "Policies granting what service Terraform creates (Aurora, KMS, Secrets Manager, IAM under a boundary). Kept explicit on purpose."
  default     = []
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
