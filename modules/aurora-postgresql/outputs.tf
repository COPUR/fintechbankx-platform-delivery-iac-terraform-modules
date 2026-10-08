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
  description = "JDBC URL with TLS required (Helm value config.DB_URL)."
  value       = "jdbc:postgresql://${aws_rds_cluster.this.endpoint}:${aws_rds_cluster.this.port}/${var.database_name}?sslmode=require"
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
