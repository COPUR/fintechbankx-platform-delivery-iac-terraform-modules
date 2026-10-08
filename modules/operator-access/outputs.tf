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
