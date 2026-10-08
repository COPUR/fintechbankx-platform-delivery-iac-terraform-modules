output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = local.provider_arn
}

output "role_arns" {
  description = "Service id -> { ecr-push, deploy, tf-plan, tf-apply } role ARNs (repository variables ECR_PUSH_ROLE_ARN, EKS_DEPLOY_ROLE_ARN_<ENV>, ...)."
  value = {
    for id in keys(var.services) : id => {
      for k, v in local.role_sets : v.kind => aws_iam_role.this[k].arn if v.id == id
    }
  }
}

output "deploy_kubernetes_groups" {
  description = "Service id -> Kubernetes group to bind to a namespaced Role (RoleBinding lives with the mesh/k8s platform repo)."
  value       = { for id, s in var.services : id => "fintechbankx:deploy:${s.namespace}" }
}
