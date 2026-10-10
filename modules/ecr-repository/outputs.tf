output "repository_url" {
  description = "Helm value image.repository."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "Repository ARN (scope CI push permissions to it)."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}
