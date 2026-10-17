output "endpoint" {
  description = "Cluster (writer) endpoint."
  value       = aws_docdb_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint."
  value       = aws_docdb_cluster.this.reader_endpoint
}

output "port" {
  description = "Port."
  value       = aws_docdb_cluster.this.port
}

output "connection_options" {
  description = "Driver options the app must use (TLS with the RDS CA bundle, no retryable writes on DocumentDB)."
  value       = "tls=true&replicaSet=rs0&readPreference=secondaryPreferred&retryWrites=false"
}

output "security_group_id" {
  description = "Cluster security group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "Storage key (ADR-023): cluster storage and snapshots. Not for secrets."
  value       = local.kms_key_arn
}

output "secrets_kms_key_arn" {
  description = "Secrets key (ADR-023, tagged fintechbankx.io/secrets=true) of docdb-master and docdb-app (grant kms:Decrypt via Secrets Manager to readers of the app secret)."
  value       = local.secrets_kms_key_arn
}

output "app_secret_name" {
  description = "Application credential secret, <env>/<slug>/docdb-app (ExternalSecret remote key)."
  value       = aws_secretsmanager_secret.app.name
}

output "app_secret_arn" {
  description = "Application credential secret ARN."
  value       = aws_secretsmanager_secret.app.arn
}

output "master_secret_arn" {
  description = "Admin credential, for the DBA bootstrap only."
  value       = aws_secretsmanager_secret.master.arn
}
