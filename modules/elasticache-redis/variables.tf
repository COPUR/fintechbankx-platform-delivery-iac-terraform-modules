variable "environment" {
  type        = string
  description = "dev, staging or prod (secret name <env>/<slug>/redis)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "service_slug" {
  type        = string
  description = "Service slug / Kubernetes service account."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.service_slug))
    error_message = "service_slug must be lowercase kebab-case."
  }
}

variable "auth_mode" {
  type        = string
  description = "token (generated AUTH token in <env>/<slug>/redis) or rbac (user_group_ids)."
  default     = "token"

  validation {
    condition     = contains(["token", "rbac"], var.auth_mode)
    error_message = "auth_mode must be token or rbac."
  }
}

variable "name" {
  type        = string
  description = "Name prefix. null uses <environment>-<service_slug>; it must fit the 40-character replication group id with the -redis suffix."
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z][a-z0-9-]{1,33}$", var.name))
    error_message = "name must be lowercase kebab-case, at most 34 characters (replication group id limit)."
  }
}

variable "engine_version" {
  type        = string
  description = "Redis engine version."
  default     = "7.1"
}

variable "node_type" {
  type        = string
  description = "Cache node type."
  default     = "cache.t4g.small"
}

variable "num_node_groups" {
  type        = number
  description = "Shards. 1 = cluster mode disabled layout."
  default     = 1
}

variable "replicas_per_node_group" {
  type        = number
  description = "Replicas per shard. >= 1 enables Multi-AZ automatic failover (use 1+ outside dev)."
  default     = 1

  validation {
    condition     = var.replicas_per_node_group >= 0 && var.replicas_per_node_group <= 5
    error_message = "replicas_per_node_group must be between 0 and 5."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets in at least two AZs."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Use subnets in at least two AZs."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to connect on 6379."
}

variable "user_group_ids" {
  type        = list(string)
  description = "ElastiCache RBAC user group ids when auth_mode = rbac (users managed outside this module)."
  default     = []
}

variable "kms_key_arn" {
  type        = string
  description = "Existing KMS key. null creates one."
  default     = null
}

variable "snapshot_retention_days" {
  type        = number
  description = "Daily snapshot retention (0 disables)."
  default     = 7
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch retention for slow and engine logs."
  default     = 30
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
