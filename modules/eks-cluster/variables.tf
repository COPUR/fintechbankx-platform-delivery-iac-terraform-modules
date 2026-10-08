variable "cluster_name" {
  type        = string
  description = "EKS cluster name, e.g. fintechbankx-prod."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,37}$", var.cluster_name))
    error_message = "cluster_name must start with a letter and be at most 38 characters (IAM role names derive from it)."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version. Check EKS standard support before changing."
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.31."
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets, one per AZ (network-vpc output private_subnet_ids)."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two AZs (three recommended)."
  }
}

variable "endpoint_public_access" {
  type        = bool
  description = "Expose the Kubernetes API publicly (restricted to endpoint_public_access_cidrs)."
  default     = false
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach a public API endpoint."
  default     = []
}

variable "cluster_log_types" {
  type        = list(string)
  description = "Control plane log types sent to CloudWatch."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.cluster_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "Unknown control plane log type."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Control plane log retention in days."
  default     = 90
}

variable "log_group_kms_key_arn" {
  type        = string
  description = "Optional KMS key for the control plane log group (key policy must allow CloudWatch Logs)."
  default     = null
}

variable "kms_key_arn" {
  type        = string
  description = "Existing KMS key for secrets and node volumes. null creates a dedicated key with rotation."
  default     = null
}

variable "cluster_admin_role_arns" {
  type        = list(string)
  description = "IAM roles granted AmazonEKSClusterAdminPolicy through EKS access entries (break-glass / platform admins)."
  default     = []
}

variable "node_groups" {
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
  description = "Managed node groups. Each spans all subnet_ids unless subnet_ids is set."
  default = {
    general = {
      instance_types = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge"]
      min_size       = 3
      max_size       = 9
      desired_size   = 3
    }
  }

  validation {
    condition = alltrue([for k, v in var.node_groups :
      v.min_size <= v.desired_size && v.desired_size <= v.max_size && contains(["ON_DEMAND", "SPOT"], v.capacity_type)
    ])
    error_message = "Each node group needs min_size <= desired_size <= max_size and capacity_type ON_DEMAND or SPOT."
  }
}

variable "addons" {
  type = map(object({
    version              = optional(string)
    configuration_values = optional(string)
  }))
  description = "EKS add-ons. null version lets EKS pick the default for the Kubernetes version; pin versions for prod."
  default = {
    vpc-cni                = {}
    kube-proxy             = {}
    coredns                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver     = {}
  }
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
