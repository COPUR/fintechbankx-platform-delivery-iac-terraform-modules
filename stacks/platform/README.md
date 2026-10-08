# stacks/platform

Status: **Proposed**. Validated with `terraform validate` and a type-check of the tfvars examples; never planned
against an AWS account or applied.

Composition root for one environment (one cell in one region, default `me-central-1`):

| Module | What it creates |
|---|---|
| [`network-vpc`](../../modules/network-vpc/README.md) | 3-AZ VPC, public/private/intra subnets, NAT per AZ (one shared NAT in dev), VPC endpoints, flow logs |
| [`eks-cluster`](../../modules/eks-cluster/README.md) | EKS, managed node groups across the private subnets, KMS secrets encryption, OIDC provider, core add-ons |
| [`msk-cluster`](../../modules/msk-cluster/README.md) | Amazon MSK, 3 brokers / 3 AZs, TLS, IAM auth, KMS, explicit topics, topic-admin policy |
| [`observability-amp`](../../modules/observability-amp/README.md) | Amazon Managed Prometheus (+ optional Managed Grafana) |
| [`ecr-repository`](../../modules/ecr-repository/README.md) | `fintechbankx/<image_name>` per service, immutable tags, scan on push |
| [`external-secrets-irsa`](../../modules/external-secrets-irsa/README.md) | IRSA role for ClusterSecretStore `aws-secrets-manager` (reads `<env>/*`) |
| [`irsa-role`](../../modules/irsa-role/README.md) | OTel collector remote-write role (`observability/otel-collector`) |
| [`github-oidc`](../../modules/github-oidc/README.md) | GitHub Actions OIDC provider and per-service ecr-push / deploy / tf-plan / tf-apply roles |

Per-service databases (Aurora, DocumentDB, Redis) are **not** here: each service owns them in its own
`deploy/terraform` (database per service).

## Use

```bash
cp environments/dev.tfvars.example environments/dev.tfvars
cp environments/dev.backend.hcl.example environments/dev.backend.hcl
terraform init -backend-config=environments/dev.backend.hcl
terraform plan -var-file=environments/dev.tfvars
```

The state bucket and lock table (`fintechbankx-terraform-state-<env>`, `fintechbankx-terraform-locks`) must exist
first; they are bootstrapped outside this stack.

## Outputs consumed elsewhere

| Output | Consumer |
|---|---|
| `vpc_id`, `private_subnet_ids`, `workload_security_group_id`, `eks_oidc_provider_arn`, `eks_oidc_provider_url` | service repos' `deploy/terraform` inputs of the same names |
| `msk_cluster_arn`, `msk_bootstrap_brokers_sasl_iam` | `msk-client-access` in service repos; `KAFKA_BOOTSTRAP_SERVERS` |
| `msk_topic_admin_policy_arn` | topic provisioning job (event-streaming repo) |
| `ecr_repository_urls`, `github_oidc_role_arns` | service repos' GitHub variables (`ECR_PUSH_ROLE_ARN`, `EKS_DEPLOY_ROLE_ARN_<ENV>`) |
| `deploy_kubernetes_groups` | mesh repo: RoleBinding per namespace |
| `external_secrets_role_arn` | mesh repo: `external-secrets` service account annotation |
| `vpc_cidr`, `private_subnet_cidrs`, `msk_security_group_id`, `msk_subnet_ids` | mesh repo `params.env` |
| `ingress_tls_secret_name` | mesh repo: gateway certificate at Secrets Manager `<env>/platform/ingress-tls` (created and filled outside Terraform; no certificate material in this repository) |
| `amp_remote_write_url`, `otel_collector_role_arn` | observability repo |

## Image names

`github_services` in the tfvars examples lists all 15 services. The image / service account names of the five
services with deployable charts come from those charts. The other ten (`payment-request-to-pay-service`,
`payment-recurring-mandates-service`, `payment-bulk-orchestration-service`, `openfinance-*-service`) follow the same
`<context>-<capability>-service` pattern and are **Proposed** until the owning squads confirm them.
