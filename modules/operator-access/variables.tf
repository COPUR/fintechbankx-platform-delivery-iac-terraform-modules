variable "name" {
  type        = string
  description = "Name prefix, normally <name_prefix>-<environment> (e.g. fintechbankx-dev)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be lowercase kebab-case, at most 41 characters."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_id" {
  type        = string
  description = "Private subnet of the host (no route from the internet; Session Manager through VPC endpoints or NAT)."
}

variable "egress_cidr_blocks" {
  type        = list(string)
  description = "Egress destinations, normally the VPC CIDR (SSM, KMS, Secrets Manager endpoints on 443; Aurora on 5432)."

  validation {
    condition     = length(var.egress_cidr_blocks) > 0 && alltrue([for c in var.egress_cidr_blocks : can(cidrhost(c, 0)) && tonumber(split("/", c)[1]) >= 8])
    error_message = "egress_cidr_blocks must be IPv4 prefixes of /8 or longer (no 0.0.0.0/0)."
  }
}

variable "egress_ports" {
  type        = list(number)
  description = "Egress TCP ports."
  default     = [443, 5432]
}

variable "instance_type" {
  type        = string
  description = "Instance type (x86_64 to match the default AMI parameter)."
  default     = "t3.small"
}

variable "ami_ssm_parameter" {
  type        = string
  description = "Public SSM parameter holding the AMI id (Amazon Linux 2023, SSM agent preinstalled)."
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key for the root volume; null uses the account's EBS default key (still encrypted)."
  default     = null
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root volume size in GiB."
  default     = 20
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Optional permissions boundary for the instance role."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}

variable "session_logging_enabled" {
  type        = bool
  description = "Create the KMS-encrypted CloudWatch log group /aws/ssm/<name>/sessions (dedicated rotating CMK) and let the host write session logs to it."
  default     = true
}

variable "session_log_retention_days" {
  type        = number
  description = "Retention of the session log group."
  default     = 365
}

variable "manage_session_manager_preferences" {
  type        = bool
  description = "Create the account/region Session Manager preferences document SSM-SessionManagerRunShell pointing at the session log group and key. Off by default: there is one per account and region, and it may already exist."
  default     = false
}

variable "session_idle_timeout_minutes" {
  type        = number
  description = "Session Manager idle timeout (minutes) in the preferences document."
  default     = 20

  validation {
    condition     = var.session_idle_timeout_minutes >= 1 && var.session_idle_timeout_minutes <= 60
    error_message = "session_idle_timeout_minutes must be 1..60."
  }
}
