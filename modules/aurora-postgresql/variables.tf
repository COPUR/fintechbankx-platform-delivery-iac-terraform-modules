variable "name" {
  type        = string
  description = "Resource name prefix, normally <env>-<service-slug> (e.g. dev-loan-lifecycle-service)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,45}$", var.name))
    error_message = "name must be lowercase kebab-case, at most 46 characters."
  }
}

variable "database_name" {
  type        = string
  description = "Initial database, db_<ctx>_<capability>_<env> (e.g. db_ln_loan_lifecycle_dev)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a lowercase PostgreSQL identifier."
  }
}

variable "master_username" {
  type        = string
  description = "Admin user name; its credential is generated and stored by RDS in Secrets Manager."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,15}$", var.master_username)) && !contains(["postgres", "admin", "rdsadmin"], var.master_username)
    error_message = "master_username must be a lowercase identifier (max 16) and not a reserved name."
  }
}

variable "engine_version" {
  type        = string
  description = "Aurora PostgreSQL engine version."
  default     = "16.4"
}

variable "instance_count" {
  type        = number
  description = "Writer plus readers. 2+ puts a reader in another AZ for failover; use 2+ outside dev."
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 15
    error_message = "instance_count must be between 1 and 15."
  }
}

variable "min_capacity" {
  type        = number
  description = "Serverless v2 minimum ACUs."
  default     = 0.5
}

variable "max_capacity" {
  type        = number
  description = "Serverless v2 maximum ACUs."
  default     = 8

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 256
    error_message = "max_capacity must be between 1 and 256 ACUs."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private or intra subnets in at least two AZs."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Aurora needs subnets in at least two Availability Zones."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to connect on 5432 (EKS cluster/node or pod security group)."

  validation {
    condition     = length(var.allowed_security_group_ids) >= 1
    error_message = "List at least one workload security group."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Existing KMS key. null creates a dedicated key with rotation."
  default     = null
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Enable IAM database authentication."
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Automated backup retention (PITR window)."
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "preferred_backup_window" {
  type        = string
  description = "Daily backup window (UTC)."
  default     = "01:00-02:00"
}

variable "preferred_maintenance_window" {
  type        = string
  description = "Weekly maintenance window (UTC)."
  default     = "sun:03:00-sun:04:00"
}

variable "deletion_protection" {
  type        = bool
  description = "Protect the cluster from deletion."
  default     = true
}

variable "performance_insights_retention_days" {
  type        = number
  description = "Performance Insights retention (7 is free tier)."
  default     = 7
}

variable "log_min_duration_statement_ms" {
  type        = number
  description = "Log statements slower than this many milliseconds."
  default     = 500
}

variable "create_app_secret" {
  type        = bool
  description = "Create the empty application credential secret."
  default     = true
}

variable "app_secret_name" {
  type        = string
  description = "Application credential secret name. Use <env>/<service-slug>/db-app so the aws-secrets-manager ClusterSecretStore (reads <env>/*) can sync it. null keeps the legacy <name>/db-app."
  default     = null
}

variable "create_migration_secret" {
  type        = bool
  description = "Create the empty schema-owner (migration) credential secret of the two-role pattern."
  default     = true
}

variable "migration_secret_name" {
  type        = string
  description = "Schema-owner (Flyway) credential secret name, <env>/<service-slug>/db-migration. null keeps <name>/db-migration."
  default     = null

  validation {
    condition     = var.migration_secret_name == null || can(regex("^[a-z0-9-]+/[a-z0-9-]+/db-migration$", var.migration_secret_name))
    error_message = "migration_secret_name must be <env>/<service-slug>/db-migration."
  }
}

variable "alarm_topic_arn" {
  type        = string
  description = "SNS topic for alarms; null disables notifications."
  default     = null
}

variable "acu_alarm_threshold_percent" {
  type        = number
  description = "ACUUtilization alarm threshold."
  default     = 85
}

variable "connections_alarm_threshold" {
  type        = number
  description = "DatabaseConnections alarm threshold."
  default     = 100
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
