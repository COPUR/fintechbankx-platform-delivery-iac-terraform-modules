variable "environment" {
  type        = string
  description = "dev, staging or prod (secret names start with it)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "service_slug" {
  type        = string
  description = "Service slug / Kubernetes service account (e.g. personal-financial-data-service)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}$", var.service_slug))
    error_message = "service_slug must be lowercase kebab-case."
  }
}

variable "name" {
  type        = string
  description = "Resource name prefix. null uses <environment>-<service_slug>."
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z][a-z0-9-]{1,50}$", var.name))
    error_message = "name must be lowercase kebab-case, at most 51 characters."
  }
}

variable "engine_version" {
  type        = string
  description = "DocumentDB engine version."
  default     = "5.0.0"
}

variable "engine_major_version" {
  type        = string
  description = "Parameter group family suffix (docdb<major>)."
  default     = "5.0"
}

variable "instance_class" {
  type        = string
  description = "Instance class."
  default     = "db.r6g.large"
}

variable "instance_count" {
  type        = number
  description = "Instances (primary + replicas). 3 spreads one per AZ; use >= 2 outside dev."
  default     = 3

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 16
    error_message = "instance_count must be between 1 and 16."
  }
}

variable "master_username" {
  type        = string
  description = "Admin user name."
  default     = "docdb_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.master_username)) && var.master_username != "admin"
    error_message = "master_username must be an identifier and not the reserved name admin."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets in at least two AZs (three recommended)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Use subnets in at least two AZs."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed on 27017."

  validation {
    condition     = length(var.allowed_security_group_ids) >= 1
    error_message = "List at least one workload security group."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Storage key override (ADR-023): cluster storage and snapshots. Must not be tagged fintechbankx.io/secrets. null creates <name>-docdb-storage."
  default     = null
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "Secrets key override (ADR-023): docdb-master and docdb-app secrets. Tag it fintechbankx.io/secrets=true. Must differ from kms_key_arn. null creates <name>-docdb-secrets."
  default     = null
}

variable "backup_retention_days" {
  type        = number
  description = "Backup retention / PITR window."
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Protect the cluster from deletion."
  default     = true
}

variable "profiler_threshold_ms" {
  type        = number
  description = "Profile operations slower than this."
  default     = 200
}

variable "connections_alarm_threshold" {
  type        = number
  description = "DatabaseConnections alarm threshold."
  default     = 500
}

variable "alarm_topic_arn" {
  type        = string
  description = "SNS topic for alarms; null disables notifications."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}

variable "observability_discovery" {
  type        = bool
  description = "Tag resources fintechbankx.io/observability=enabled so the YACE CloudWatch exporter discovers them."
  default     = true
}
