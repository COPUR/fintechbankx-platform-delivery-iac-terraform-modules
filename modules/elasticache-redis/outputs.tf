output "primary_endpoint" {
  description = "Primary endpoint (TLS, port 6379)."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "configuration_endpoint" {
  description = "Configuration endpoint (cluster mode only)."
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}

output "security_group_id" {
  description = "Redis security group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "Encryption-at-rest key."
  value       = local.kms_key_arn
}

output "secret_name" {
  description = "Connection secret <env>/<slug>/redis (ExternalSecret remote key)."
  value       = aws_secretsmanager_secret.redis.name
}

output "secret_arn" {
  description = "Connection secret ARN."
  value       = aws_secretsmanager_secret.redis.arn
}
