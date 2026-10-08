variable "name" {
  type        = string
  description = "Name prefix, e.g. fintechbankx-prod-mec1."
}

variable "cidr_block" {
  type        = string
  description = "VPC IPv4 CIDR (a /16 is recommended so EKS pods get room)."

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) <= 20
    error_message = "cidr_block must be a valid IPv4 CIDR of /20 or larger."
  }
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones to use. null picks the first az_count AZs of the region."
  default     = null
}

variable "az_count" {
  type        = number
  description = "Number of AZs when azs is null."
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "az_count must be between 2 and 6 (3 recommended)."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Optional explicit private subnet CIDRs (one per AZ)."
  default     = []
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Optional explicit public subnet CIDRs (one per AZ)."
  default     = []
}

variable "intra_subnet_cidrs" {
  type        = list(string)
  description = "Optional explicit intra (no internet route) subnet CIDRs (one per AZ)."
  default     = []
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create NAT gateways for private subnet egress."
  default     = true
}

variable "single_nat_gateway" {
  type        = bool
  description = "One shared NAT gateway (cheaper, not AZ-resilient; dev only). false = one NAT per AZ."
  default     = false
}

variable "interface_endpoints" {
  type        = list(string)
  description = "Interface endpoint service suffixes."
  default     = ["ecr.api", "ecr.dkr", "sts", "secretsmanager", "ssm", "logs"]
}

variable "eks_cluster_name" {
  type        = string
  description = "Optional EKS cluster name for kubernetes.io/cluster/<name> subnet tags."
  default     = null
}

variable "enable_flow_logs" {
  type        = bool
  description = "Send VPC flow logs to CloudWatch Logs."
  default     = true
}

variable "flow_log_retention_days" {
  type        = number
  description = "Flow log retention in days."
  default     = 90
}

variable "flow_log_kms_key_arn" {
  type        = string
  description = "Optional KMS key for the flow log group (key policy must allow CloudWatch Logs)."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
