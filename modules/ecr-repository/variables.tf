variable "name" {
  type        = string
  description = "Repository name, e.g. fintechbankx/loan-lifecycle-service."

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name)) && length(var.name) <= 256
    error_message = "name must be a valid lowercase ECR repository name."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key ARN. null uses the AWS-managed aws/ecr key (still KMS)."
  default     = null
}

variable "max_tagged_images" {
  type        = number
  description = "Number of images to retain."
  default     = 50

  validation {
    condition     = var.max_tagged_images >= 5
    error_message = "Keep at least 5 images so rollbacks stay possible."
  }
}

variable "untagged_expiry_days" {
  type        = number
  description = "Days after which untagged images expire."
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}

variable "pull_principal_arns" {
  type        = list(string)
  description = "Extra principals (e.g. other workload accounts) allowed to pull. Same-account IAM access needs no entry."
  default     = []
}

variable "force_delete" {
  type        = bool
  description = "Allow deleting the repository while it still holds images (keep false outside sandboxes)."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
