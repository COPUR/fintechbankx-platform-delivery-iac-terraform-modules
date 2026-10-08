output "role_arn" {
  description = "Role ARN for the service account annotation eks.amazonaws.com/role-arn (Helm serviceAccount.roleArn)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}
