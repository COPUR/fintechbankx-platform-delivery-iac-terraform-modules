# Aurora PostgreSQL Serverless v2 owned by exactly one service (database per
# service). Generalises what loan-lifecycle-core's deploy/terraform does
# inline: dedicated KMS key, rds.force_ssl, subnet group across AZs, a
# security group that only admits the workload security group(s), an
# RDS-managed admin credential, an application credential secret container
# (value written by the DBA bootstrap, never by Terraform) and alarms.
# Also used for the Keycloak database (no separate module).

locals {
  tags         = merge({ ManagedBy = "terraform", Module = "aurora-postgresql", Database = var.database_name }, var.observability_discovery ? { "fintechbankx.io/observability" = "enabled" } : {}, var.tags)
  engine_major = split(".", var.engine_version)[0]
  kms_key_arn  = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn
  alarm_action = var.alarm_topic_arn == null ? [] : [var.alarm_topic_arn]
}

# --- Encryption -------------------------------------------------------------

resource "aws_kms_key" "this" {
  count                   = var.kms_key_arn == null ? 1 : 0
  description             = "Encrypts ${var.database_name} storage, snapshots, Performance Insights and credentials"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  # Lets External Secrets Operator decrypt the app credential (contract addendum).
  tags = merge(local.tags, { "fintechbankx.io/secrets" = "true" })
}

resource "aws_kms_alias" "this" {
  count         = var.kms_key_arn == null ? 1 : 0
  name          = "alias/${var.name}-db"
  target_key_id = aws_kms_key.this[0].key_id
}

# --- Network ----------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-db"
  description = "PostgreSQL access for ${var.name} workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-db" })
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from workload security group ${count.index}"
}

# --- Cluster ----------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name   = "${var.name}-aurora-pg${local.engine_major}"
  family = "aurora-postgresql${local.engine_major}"
  tags   = local.tags

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement_ms)
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = "${var.name}-aurora"
  engine                              = "aurora-postgresql"
  engine_mode                         = "provisioned"
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = local.kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.this.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  storage_encrypted                   = true
  kms_key_id                          = local.kms_key_arn
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  backup_retention_period             = var.backup_retention_days
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-aurora-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  tags                                = local.tags

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }
}

resource "aws_rds_cluster_instance" "this" {
  count                                 = var.instance_count
  identifier                            = "${var.name}-aurora-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.this.id
  instance_class                        = "db.serverless"
  engine                                = aws_rds_cluster.this.engine
  engine_version                        = aws_rds_cluster.this.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_days
  promotion_tier                        = count.index
  tags                                  = local.tags
}

# Two-role pattern (platform contract "Database roles"):
#   db-migration  owner role of the service schema, used only by Flyway
#                 (DDL); DB_MIGRATION_* in the migration step.
#   db-app        runtime role (DB_USERNAME/DB_PASSWORD) with only the DML
#                 grants the service needs, no DDL.
# The DBA bootstrap creates both roles and writes {"username", "password"}
# into these secrets; Terraform only creates the empty containers and never
# holds the values.

# Runtime (application) credential container.
resource "aws_secretsmanager_secret" "app" {
  count                   = var.create_app_secret ? 1 : 0
  name                    = var.app_secret_name != null ? var.app_secret_name : "${var.name}/db-app"
  description             = "Application credential for ${var.database_name}"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 7
  tags                    = local.tags
}

# Schema owner (migration) credential container.
resource "aws_secretsmanager_secret" "migration" {
  count                   = var.create_migration_secret ? 1 : 0
  name                    = var.migration_secret_name != null ? var.migration_secret_name : "${var.name}/db-migration"
  description             = "Schema owner (Flyway migration) credential for ${var.database_name}"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 7
  tags                    = local.tags
}

# --- Alarms -----------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "acu" {
  alarm_name          = "${var.name}-aurora-acu-high"
  alarm_description   = "Aurora is near its max ACUs; raise max_capacity or look for a runaway query."
  namespace           = "AWS/RDS"
  metric_name         = "ACUUtilization"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.acu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action
  ok_actions          = local.alarm_action
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  alarm_name          = "${var.name}-aurora-connections-high"
  alarm_description   = "Connections near the pool budget (HPA max replicas x pool size)."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.connections_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  alarm_name          = "${var.name}-aurora-freeable-memory-low"
  alarm_description   = "Writer is short of memory; capacity floor may be too low."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_action
  tags                = local.tags
}
