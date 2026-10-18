variable "environment" {
  type        = string
  description = "Environment (dev, staging, prod); part of the policy name."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "service_slug" {
  type        = string
  description = "Service slug (e.g. accounts-ledger-service); part of the policy name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.service_slug))
    error_message = "service_slug must be a lowercase kebab-case slug."
  }
}

variable "database_name" {
  type        = string
  description = "The service's database (e.g. db_acc_accounts_ledger_dev); the login SQL refuses to run in any other database."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a lowercase PostgreSQL identifier."
  }
}

variable "cluster_resource_id" {
  type        = string
  description = "Aurora cluster resource id (aws_rds_cluster cluster_resource_id, cluster-<ID>), not the cluster identifier: rds-db:connect resources name it."

  validation {
    condition     = can(regex("^cluster-[A-Z0-9]{16,40}$", var.cluster_resource_id))
    error_message = "cluster_resource_id must be the cluster resource id (cluster-<uppercase letters and digits>)."
  }
}

variable "operator_group_role" {
  type        = string
  description = "NOLOGIN group role the operator logins belong to. The service's own schema migration grants it what operators may do; this module grants it nothing but CONNECT."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{2,62}$", var.operator_group_role)) && !can(regex("^(pg_|rds_|op_|postgres$|rdsadmin$)", var.operator_group_role))
    error_message = "operator_group_role must be a lowercase identifier that is not a system name (pg_*, rds_*, postgres, rdsadmin) and not an operator login (op_*)."
  }
}

variable "operators" {
  type        = map(string)
  description = "IAM Identity Center user name (the session name of their permission-set role) => their own database login (op_<name>). One login per person; removing a person here removes their connect permission and, on the next run of the login SQL, their login."

  validation {
    condition = length(var.operators) > 0 && length(var.operators) <= 20 && alltrue([
      for user, login in var.operators :
      can(regex("^[A-Za-z0-9+=,.@_-]{2,64}$", user)) && can(regex("^op_[a-z][a-z0-9_]{1,59}$", login))
    ]) && length(distinct(values(var.operators))) == length(var.operators)
    error_message = "operators must map 1 to 20 Identity Center user names (2-64 characters of A-Z a-z 0-9 + = , . @ _ -, so no * or ?) to distinct logins op_<lowercase name>."
  }
}

variable "reserved_db_users" {
  type        = list(string)
  description = "The service's own database users (master, runtime and migration users). None of them may be the group or an operator login, and the login SQL takes them out of the group if they were ever put in."

  validation {
    condition     = length(var.reserved_db_users) > 0 && alltrue([for u in var.reserved_db_users : can(regex("^[a-z][a-z0-9_]{0,62}$", u))])
    error_message = "reserved_db_users must list the service's own database users (lowercase identifiers)."
  }
}

variable "connection_limit" {
  type        = number
  description = "Concurrent sessions per operator login."
  default     = 2

  validation {
    condition     = var.connection_limit >= 1 && var.connection_limit <= 10 && floor(var.connection_limit) == var.connection_limit
    error_message = "connection_limit must be a whole number from 1 to 10."
  }
}

variable "idle_in_transaction_timeout_seconds" {
  type        = number
  description = "idle_in_transaction_session_timeout of each operator login, in seconds: a session left idle inside a transaction is ended, so it cannot hold row locks the service's own jobs (the outbox relay's discard step) wait for."
  default     = 60

  validation {
    condition     = var.idle_in_transaction_timeout_seconds >= 5 && var.idle_in_transaction_timeout_seconds <= 600 && floor(var.idle_in_transaction_timeout_seconds) == var.idle_in_transaction_timeout_seconds
    error_message = "idle_in_transaction_timeout_seconds must be a whole number from 5 to 600."
  }
}

variable "read_only" {
  type        = bool
  description = "Logins that may only read, such as a pre-cutover check: each login defaults every transaction to read only, and the login SQL stops when the group can change anything in the database (a write, CREATE or ownership the service's migration gave it, or EXECUTE on a SECURITY DEFINER function). The policy is named <env>-<slug>-db-readonly-login instead of -db-operator-login."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Resource tags."
  default     = {}
}
