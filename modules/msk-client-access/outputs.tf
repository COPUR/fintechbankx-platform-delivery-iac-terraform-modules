output "policy_arn" {
  description = "Managed policy ARN to attach to the service's IRSA role."
  value       = aws_iam_policy.this.arn
}

output "policy_json" {
  description = "Rendered policy document (for review and tests)."
  value       = data.aws_iam_policy_document.this.json
}
