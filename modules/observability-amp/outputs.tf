output "workspace_id" {
  description = "AMP workspace id."
  value       = aws_prometheus_workspace.this.id
}

output "workspace_arn" {
  description = "AMP workspace ARN."
  value       = aws_prometheus_workspace.this.arn
}

output "prometheus_endpoint" {
  description = "AMP workspace endpoint (query base URL)."
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "remote_write_url" {
  description = "Remote write URL for Prometheus/OTel collector (SigV4, service aps)."
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "remote_write_policy_arn" {
  description = "Attach to the collector's IRSA role."
  value       = aws_iam_policy.remote_write.arn
}

output "query_policy_arn" {
  description = "Attach to roles that query metrics (Grafana, KEDA, alert tooling)."
  value       = aws_iam_policy.query.arn
}

output "grafana_endpoint" {
  description = "Managed Grafana URL (null when disabled)."
  value       = var.enable_grafana ? aws_grafana_workspace.this[0].endpoint : null
}
