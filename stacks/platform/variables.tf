variable "aws_region" {
  type        = string
  description = "Region of the cell."
  default     = "me-central-1"
}

variable "environment" {
  type        = string
  description = "dev, staging or prod."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for platform resource names."
  default     = "fintechbankx"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR (a /16 per environment, non-overlapping across environments)."
}

variable "az_count" {
  type        = number
  description = "Availability Zones (3 for staging/prod)."
  default     = 3
}

variable "single_nat_gateway" {
  type        = bool
  description = "Share one NAT gateway (dev only, cost over resilience)."
  default     = false
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.31"
}

variable "eks_endpoint_public_access" {
  type        = bool
  description = "Expose the Kubernetes API publicly (allow-listed CIDRs only)."
  default     = false
}

variable "eks_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to a public API endpoint."
  default     = []
}

variable "eks_cluster_admin_role_arns" {
  type        = list(string)
  description = "IAM roles with cluster-admin access entries."
  default     = []
}

variable "eks_node_groups" {
  type = map(object({
    instance_types             = list(string)
    capacity_type              = optional(string, "ON_DEMAND")
    ami_type                   = optional(string, "AL2023_x86_64_STANDARD")
    min_size                   = number
    max_size                   = number
    desired_size               = number
    disk_size_gb               = optional(number, 50)
    max_unavailable_percentage = optional(number, 25)
    subnet_ids                 = optional(list(string))
    labels                     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
  }))
  description = "Managed node groups (see modules/eks-cluster)."
  default = {
    general = {
      instance_types = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge"]
      min_size       = 3
      max_size       = 9
      desired_size   = 3
    }
  }
}

variable "kafka_version" {
  type        = string
  description = "MSK Kafka version."
  default     = "3.6.0"
}

variable "msk_broker_count" {
  type        = number
  description = "MSK brokers (multiple of az_count)."
  default     = 3
}

variable "msk_broker_instance_type" {
  type        = string
  description = "MSK broker instance type."
  default     = "kafka.m7g.large"
}

variable "msk_broker_volume_size_gb" {
  type        = number
  description = "EBS per broker (GiB)."
  default     = 500
}

variable "enable_managed_grafana" {
  type        = bool
  description = "Create an Amazon Managed Grafana workspace (check regional availability)."
  default     = false
}

variable "create_ecr_repositories" {
  type        = bool
  description = "Create ECR repositories in this environment's account (false when a shared tooling account holds them)."
  default     = true
}

variable "service_repositories" {
  type        = map(string)
  description = "Extra service id -> image name entries for ECR beyond github_services (repositories are fintechbankx/<image name>)."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.service_repositories : can(regex("^svc-[a-z0-9]+-[a-z0-9-]+$", k)) && can(regex("^[a-z][a-z0-9-]+$", v))])
    error_message = "Keys must be service ids (svc-<ctx>-<cap>) and values kebab-case image names."
  }
}

variable "msk_enhanced_monitoring" {
  type        = string
  description = "MSK CloudWatch enhanced monitoring level (the observability repo expects PER_BROKER)."
  default     = "PER_BROKER"
}

variable "create_grafana_database" {
  type        = bool
  description = "Create the small Aurora PostgreSQL database for Grafana (staging, prod). dev falls back to per-pod SQLite."
  default     = true
}

variable "observability_log_retention_days" {
  type        = number
  description = "Expiry for objects in the Tempo and Loki buckets (backstop; the apps enforce their own retention)."
  default     = 400
}

variable "log_retention_days" {
  type        = number
  description = "Retention for platform log groups."
  default     = 90
}

variable "alarm_topic_arn" {
  type        = string
  description = "SNS topic for platform alarms; null disables notifications."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Extra tags (cost centre, data classification)."
  default     = {}
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Create the GitHub OIDC provider in this account (false if another stack already did)."
  default     = true
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "Existing GitHub OIDC provider ARN when create_github_oidc_provider is false."
  default     = null
}

variable "github_services" {
  type = map(object({
    repository          = string
    image_name          = string
    namespace           = string
    terraform_state_key = string
    # Optional: name prefix of the service's AWS resources (default <env>-<image_name>).
    resource_name_prefix = optional(string)
  }))
  description = "Service id -> GitHub repository, image name, context namespace and its deploy/terraform state key, one per service (see modules/github-oidc)."
  default     = {}
}

variable "ecr_registry_account_id" {
  type        = string
  description = "Account holding the fintechbankx/* ECR repositories when this account does not (create_ecr_repositories = false); deploy roles pull from it for cosign verify. null = this account."
  default     = null
}

variable "terraform_state_bucket" {
  type        = string
  description = "State bucket; null uses <name_prefix>-terraform-state-<environment>."
  default     = null
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

variable "ci_apply_policy_arns" {
  type        = list(string)
  description = "Policies attached to every service tf-apply role."
  default     = []
}

variable "ci_permissions_boundary_arn" {
  type        = string
  description = "Permissions boundary applied to every CI role."
  default     = null
}

variable "bind_platform_workflow_ref" {
  type        = bool
  description = "Passed to github-oidc: trust CI roles only from the platform's reusable workflows at platform_workflow_refs. Turn on together with the job_workflow_ref sub-claim customization in every service repository."
  default     = false
}

variable "platform_workflow_refs" {
  type        = list(string)
  description = "Passed to github-oidc: release tags (refs/tags/...) or 40-character release SHAs of the platform workflows."
  default     = ["refs/tags/v*"]
}
