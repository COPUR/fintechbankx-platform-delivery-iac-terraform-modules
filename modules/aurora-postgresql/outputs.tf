output "cluster_identifier" {
  description = "Aurora cluster identifier."
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Aurora cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Cluster resource id (for rds-db:connect IAM policies)."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "endpoint" {
  description = "Writer endpoint."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.this.port
}

output "jdbc_url" {
  description = "Writer JDBC URL that verifies the server certificate and host name (sslmode=verify-full) against the RDS CA bundle at ssl_root_cert_path (Helm value config.DB_URL)."
  value       = "jdbc:postgresql://${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${var.database_name}?${local.tls_params}"
}

output "reader_jdbc_url" {
  description = "Reader JDBC URL with the same certificate verification as jdbc_url."
  value       = "jdbc:postgresql://${aws_rds_cluster.this.reader_endpoint}:${aws_rds_cluster.this.port}/${var.database_name}?${local.tls_params}"
}

output "ssl_root_cert_path" {
  description = "Container path of the RDS CA bundle the JDBC URLs trust (ConfigMap rds-ca-bundle, key global-bundle.pem, mounted by the service chart)."
  value       = var.ssl_root_cert_path
}

output "security_group_id" {
  description = "Database security group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "KMS key protecting storage and credentials (grant kms:Decrypt to the workload)."
  value       = local.kms_key_arn
}

output "app_secret_arn" {
  description = "Application credential secret ARN."
  value       = var.create_app_secret ? aws_secretsmanager_secret.app[0].arn : null
}

output "app_secret_name" {
  description = "Application credential secret name (Helm value externalSecret.remoteSecretName)."
  value       = var.create_app_secret ? aws_secretsmanager_secret.app[0].name : null
}

output "master_user_secret_arn" {
  description = "RDS-managed admin credential, for the DBA bootstrap only."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "migration_secret_arn" {
  description = "ARN of the schema-owner (migration) credential secret, or null."
  value       = var.create_migration_secret ? aws_secretsmanager_secret.migration[0].arn : null
}

output "migration_secret_name" {
  description = "Name of the schema-owner (migration) credential secret, or null."
  value       = var.create_migration_secret ? aws_secretsmanager_secret.migration[0].name : null
}

output "role_bootstrap_sql" {
  description = "DBA bootstrap SQL of the two-role pattern (run once as the RDS admin, in database_name): owner role owns the schema and runs Flyway; runtime role gets USAGE and DML only. No passwords: the DBA sets them from the db-migration and db-app secrets. null unless schema_name, app_role_name and migration_role_name are set."
  value       = local.role_bootstrap_sql
}
