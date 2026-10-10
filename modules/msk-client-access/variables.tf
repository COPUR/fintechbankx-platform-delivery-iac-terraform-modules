variable "service_id" {
  type        = string
  description = "Service id (svc-<ctx>-<cap>), used in descriptions."

  validation {
    condition     = can(regex("^svc-[a-z0-9]+-[a-z0-9-]+$", var.service_id))
    error_message = "service_id must follow svc-<ctx>-<cap>."
  }
}

variable "policy_name" {
  type        = string
  description = "IAM policy name, e.g. <env>-<service-slug>-msk."
}

variable "cluster_arn" {
  type        = string
  description = "MSK cluster ARN (msk-cluster output cluster_arn)."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kafka:[a-z0-9-]+:[0-9]{12}:cluster/[^/]+/[^/]+$", var.cluster_arn))
    error_message = "cluster_arn must be an MSK cluster ARN."
  }
}

variable "produce_topic_prefixes" {
  type        = list(string)
  description = "The service's own aggregates as evt.<ctx>.<aggregate>. prefixes (e.g. [\"evt.ln.loan.\"])."
  default     = []

  validation {
    condition     = alltrue([for p in var.produce_topic_prefixes : can(regex("^evt\\.[a-z0-9]+\\.[a-z0-9-]+\\.$", p))])
    error_message = "Each produce prefix must be exactly evt.<ctx>.<aggregate>. (no wildcards, trailing dot)."
  }
}

variable "produce_topics" {
  type        = list(string)
  description = "Exact topics the service writes, evt.<ctx>.<aggregate>.<event>.v<major> (optional; DLQs are consumer-owned and already covered by produce_topic_prefixes)."
  default     = []

  validation {
    condition     = alltrue([for t in var.produce_topics : can(regex("^evt\\.[a-z0-9]+\\.[a-z0-9-]+\\.[a-z0-9-]+\\.v[0-9]+$", t))])
    error_message = "Each produce topic must be a full name evt.<ctx>.<aggregate>.<event>.v<major> without wildcards."
  }
}

variable "consume_topics" {
  type        = list(string)
  description = "Topics the service consumes, full names (evt.<ctx>.<aggregate>.<event>.v<major>) or an aggregate prefix ending in .* ."
  default     = []

  validation {
    condition = alltrue([for t in var.consume_topics :
      can(regex("^evt\\.[a-z0-9]+\\.[a-z0-9-]+\\.([a-z0-9-]+\\.v[0-9]+|\\*)$", t))
    ])
    error_message = "Each consumed topic must be evt.<ctx>.<aggregate>.<event>.v<major> or evt.<ctx>.<aggregate>.*"
  }
}

variable "consumer_groups" {
  type        = list(string)
  description = "Declared consumer groups cg.<service-id>.<purpose>.v<major>."
  default     = []

  validation {
    condition     = alltrue([for g in var.consumer_groups : can(regex("^cg\\.svc-[a-z0-9]+-[a-z0-9-]+\\.[a-z0-9-]+\\.v[0-9]+$", g))])
    error_message = "Consumer groups must be cg.<service-id>.<purpose>.v<major>."
  }
}

variable "consumer_group_prefixes" {
  type        = list(string)
  description = "Optional prefix form cg.<service-id>. (covers every group of the service)."
  default     = []

  validation {
    condition     = alltrue([for g in var.consumer_group_prefixes : can(regex("^cg\\.svc-[a-z0-9]+-[a-z0-9-]+\\.$", g))])
    error_message = "Consumer group prefixes must be exactly cg.<service-id>."
  }
}

variable "transactional_id_prefixes" {
  type        = list(string)
  description = "Optional transactional.id prefixes for transactional producers (normally the service id)."
  default     = []

  validation {
    condition     = alltrue([for t in var.transactional_id_prefixes : length(t) > 0 && !strcontains(t, "*")])
    error_message = "Transactional id prefixes must be non-empty and contain no wildcard."
  }
}

variable "attach_to_role_names" {
  type        = list(string)
  description = "IAM role names (e.g. the service's IRSA role) to attach the policy to."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
