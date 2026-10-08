variable "cluster_name" {
  type        = string
  description = "MSK cluster name, e.g. fintechbankx-prod-events."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,63}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and contain letters, digits and dashes."
  }
}

variable "kafka_version" {
  type        = string
  description = "Apache Kafka version supported by Amazon MSK (contract: 3.6+)."
  default     = "3.6.0"

  validation {
    condition     = can(regex("^(3\\.([6-9]|[1-9][0-9])|[4-9])\\.", var.kafka_version))
    error_message = "kafka_version must be 3.6 or newer."
  }
}

variable "number_of_broker_nodes" {
  type        = number
  description = "Broker count; a multiple of the subnet (AZ) count. 3 = one broker per AZ."
  default     = 3

  validation {
    condition     = var.number_of_broker_nodes >= 3
    error_message = "At least 3 brokers are needed for RF 3 with min.insync.replicas 2."
  }
}

variable "broker_instance_type" {
  type        = string
  description = "Broker instance type."
  default     = "kafka.m7g.large"

  validation {
    condition     = startswith(var.broker_instance_type, "kafka.")
    error_message = "broker_instance_type must be an MSK instance type (kafka.*)."
  }
}

variable "broker_volume_size_gb" {
  type        = number
  description = "EBS volume per broker in GiB."
  default     = 500
}

variable "provisioned_throughput_mibps" {
  type        = number
  description = "Optional EBS provisioned throughput per broker (MiB/s); null disables."
  default     = null
}

variable "vpc_id" {
  type        = string
  description = "VPC id."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets, one per AZ (2 or 3)."

  validation {
    condition     = length(var.subnet_ids) >= 2 && length(var.subnet_ids) <= 3
    error_message = "MSK needs 2 or 3 subnets in distinct AZs (3 recommended)."
  }
}

variable "client_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to connect on 9098 (EKS cluster/node security group)."
  default     = []
}

variable "monitoring_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to scrape exporters on 11001-11002."
  default     = []
}

variable "enable_open_monitoring" {
  type        = bool
  description = "Enable Prometheus JMX and node exporters."
  default     = true
}

variable "enhanced_monitoring" {
  type        = string
  description = "CloudWatch enhanced monitoring level."
  default     = "PER_TOPIC_PER_BROKER"

  validation {
    condition     = contains(["DEFAULT", "PER_BROKER", "PER_TOPIC_PER_BROKER", "PER_TOPIC_PER_PARTITION"], var.enhanced_monitoring)
    error_message = "Unknown enhanced_monitoring level."
  }
}

variable "server_properties_overrides" {
  type        = map(string)
  description = "Extra or overriding broker properties. auto.create.topics.enable, default.replication.factor and min.insync.replicas cannot be weakened."
  default     = {}

  validation {
    condition = (
      lookup(var.server_properties_overrides, "auto.create.topics.enable", "false") == "false" &&
      tonumber(lookup(var.server_properties_overrides, "default.replication.factor", "3")) >= 3 &&
      tonumber(lookup(var.server_properties_overrides, "min.insync.replicas", "2")) >= 2 &&
      lookup(var.server_properties_overrides, "unclean.leader.election.enable", "false") == "false"
    )
    error_message = "Overrides must keep auto.create.topics.enable=false, RF >= 3, min.insync.replicas >= 2 and unclean leader election off."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Existing KMS key for encryption at rest. null creates a dedicated key."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Broker log retention in CloudWatch."
  default     = 30
}

variable "log_group_kms_key_arn" {
  type        = string
  description = "Optional KMS key for the broker log group."
  default     = null
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

variable "create_topic_admin_policy" {
  type        = bool
  description = "Create the topic-admin IAM policy for the topic provisioning job."
  default     = true
}

variable "topic_admin_prefixes" {
  type        = list(string)
  description = "Topic name prefixes the provisioning job may create and alter."
  default     = ["evt."]

  validation {
    condition     = length(var.topic_admin_prefixes) > 0 && alltrue([for p in var.topic_admin_prefixes : length(p) > 0 && !strcontains(p, "*")])
    error_message = "List non-empty prefixes without wildcards."
  }
}

variable "observability_discovery" {
  type        = bool
  description = "Tag resources fintechbankx.io/observability=enabled so the YACE CloudWatch exporter discovers them."
  default     = true
}
