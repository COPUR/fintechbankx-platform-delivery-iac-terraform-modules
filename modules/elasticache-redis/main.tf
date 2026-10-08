# Optional Redis (ElastiCache replication group) for a service that needs a
# cache. Encrypted at rest (KMS) and in transit (TLS required), Multi-AZ with
# automatic failover when there is at least one replica, slow and engine logs
# in CloudWatch. Authentication:
#  - auth_mode "token" (default): a generated AUTH token, stored with the
#    connection details in Secrets Manager <env>/<slug>/redis for the
#    aws-secrets-manager ClusterSecretStore. The token is also in (encrypted)
#    Terraform state.
#  - auth_mode "rbac": ElastiCache RBAC user groups managed outside the module.

locals {
  name        = var.name != null ? var.name : "${var.environment}-${var.service_slug}"
  tags        = merge({ ManagedBy = "terraform", Module = "elasticache-redis", Service = var.service_slug }, var.tags)
  use_token   = var.auth_mode == "token"
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn
  multi_az    = var.replicas_per_node_group >= 1
}

resource "aws_kms_key" "this" {
  count                   = var.kms_key_arn == null ? 1 : 0
  description             = "ElastiCache ${local.name} encryption at rest"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.tags, { "fintechbankx.io/secrets" = "true" })
}

resource "random_password" "auth" {
  count   = local.use_token ? 1 : 0
  length  = 64
  special = false
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${local.name}-redis"
  subnet_ids = var.subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${local.name}-redis"
  description = "Redis access for ${local.name} workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.name}-redis" })
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Redis from workload security group ${count.index}"
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = toset(["slow-log", "engine-log"])
  name              = "/aws/elasticache/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_elasticache_replication_group" "this" {
  lifecycle {
    precondition {
      condition     = length("${local.name}-redis") <= 40
      error_message = "Replication group id <name>-redis exceeds 40 characters; set a shorter name."
    }
    precondition {
      condition     = var.auth_mode == "token" || length(var.user_group_ids) > 0
      error_message = "auth_mode rbac needs user_group_ids."
    }
  }

  replication_group_id       = "${local.name}-redis"
  description                = "Redis for ${local.name}"
  engine                     = "redis"
  engine_version             = var.engine_version
  node_type                  = var.node_type
  port                       = 6379
  num_node_groups            = var.num_node_groups
  replicas_per_node_group    = var.replicas_per_node_group
  automatic_failover_enabled = local.multi_az
  multi_az_enabled           = local.multi_az
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.this.id]
  at_rest_encryption_enabled = true
  kms_key_id                 = local.kms_key_arn
  transit_encryption_enabled = true
  auth_token                 = local.use_token ? random_password.auth[0].result : null
  auth_token_update_strategy = local.use_token ? "ROTATE" : null
  user_group_ids             = local.use_token ? null : var.user_group_ids
  snapshot_retention_limit   = var.snapshot_retention_days
  snapshot_window            = "02:00-03:00"
  maintenance_window         = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true
  apply_immediately          = false
  tags                       = local.tags

  dynamic "log_delivery_configuration" {
    for_each = aws_cloudwatch_log_group.this
    content {
      destination      = log_delivery_configuration.value.name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = log_delivery_configuration.key
    }
  }
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.environment}/${var.service_slug}/redis"
  description             = "Redis connection for ${local.name} (TLS)"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 7
  # Terraform writes this value, so the tf-plan role may refresh it (github-oidc).
  tags = merge(local.tags, { "fintechbankx.io/value-in-state" = "true" })
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    host       = aws_elasticache_replication_group.this.primary_endpoint_address
    reader     = aws_elasticache_replication_group.this.reader_endpoint_address
    port       = 6379
    tls        = true
    auth_token = local.use_token ? random_password.auth[0].result : null
  })
}
