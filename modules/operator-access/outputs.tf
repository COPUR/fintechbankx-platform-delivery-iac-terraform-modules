output "operator_security_group_id" {
  description = "Security group of the operator host; add it to a service database's allowed_security_group_ids to let operators reach it."
  value       = aws_security_group.this.id
}

output "instance_id" {
  description = "Operator host instance id (target of aws ssm start-session)."
  value       = aws_instance.this.id
}

output "instance_role_arn" {
  description = "Instance role (AmazonSSMManagedInstanceCore only)."
  value       = aws_iam_role.this.arn
}

output "session_log_group_name" {
  description = "KMS-encrypted CloudWatch log group of Session Manager sessions (null when session_logging_enabled is false)."
  value       = var.session_logging_enabled ? aws_cloudwatch_log_group.session_logs[0].name : null
}

output "session_log_kms_key_arn" {
  description = "CMK of the session logs and session data (null when session_logging_enabled is false)."
  value       = var.session_logging_enabled ? aws_kms_key.session_logs[0].arn : null
}
