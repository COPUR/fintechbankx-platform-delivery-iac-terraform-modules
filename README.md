# fintechbankx-platform-delivery-iac-terraform-modules

Bu repository, FinTechBankX DDD/EDA dönüşümünde **svc-iac-modules** servis yetkinliğinin kaynak kodunu, kontratlarını ve operasyonel guardrail'lerini içerir.

## Sorumluluk ve Sahiplik
| Alan | Değer |
|---|---|
| Organizasyon Modeli | Spotify Model (Tribe/Squad) |
| Tribe | Platform & Enablement Tribe |
| Squad | Infrastructure and Data Platform Squad |
| Repo Kümesi (Capability) | platform |
| Service ID | svc-iac-modules |
| Bounded Context | terraform_modules |
| Wave | 0 |
| Mimari Yaklaşım | DDD + Hexagonal + Event-Driven |

## Sorumluluk Sınırları
- Bu repo kendi bounded context domain modelinin tek yetkili sahibidir.
- Domain kuralları altyapıdan bağımsız tutulur; entegrasyonlar port/adapter katmanında yönetilir.
- API/Event kontratları geriye dönük uyumluluk kontrolleri ile korunur.
- Güvenlik guardrail'leri (mTLS, token doğrulama, idempotency, log hijyeni) CI/CD ile zorlanır.

## Kapsam
### In Scope
- terraform_modules bağlamına ait uygulama kodu, testler ve otomasyon.
- Bu servise ait OpenAPI/AsyncAPI veya şema artefaktları.
- Bu servisin çalışma zamanı operasyonları (gözlemlenebilirlik, release, rollback).

### Out of Scope
- Diğer bounded context'lerin iş kuralları ve veri sahipliği.
- Paylaşımlı DB anti-pattern'i; cross-context doğrudan tablo erişimi.
- Platform dışı gizli bilgi/anahtar yönetimi (merkezi policy dışında local hardcode).

## Mühendislik Standartları
- **TDD öncelikli** geliştirme, birim test + entegrasyon testi.
- **Clean Architecture**: Domain katmanı framework bağımsız.
- **12-Factor** ve environment-driven configuration.
- **FAPI odaklı güvenlik** (OIDC/OAuth2, mTLS, DPoP gereksinimleri ilgili servislerde).
- **PII güvenliği**: loglarda maskeleme, secret'ların source/env içine yazılmaması.

## Branching ve Release Akışı
- Uzun ömürlü branch'ler: `main`, `dev`, `staging`, `local`.
- Feature branch kuralı: `codex/<kisa-aciklama>`.
- Release yaklaşımı: PR + required status checks + tag tabanlı sürümleme.

## Dokümantasyon ve Referanslar
- [Enterprise Architecture Hub](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture)
- [Secure Microservices Architecture](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture/blob/main/docs/architecture/overview/SECURE_MICROSERVICES_ARCHITECTURE.md)
- [Service Data Ownership Matrix](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture/blob/main/docs/enterprisearchitecture/implementation-development/SERVICE_DATA_OWNERSHIP_MATRIX.md)
- [Service API Contracts Index](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture/blob/main/docs/enterprisearchitecture/implementation-development/SERVICE_API_CONTRACTS_INDEX.md)
- [Transformation Plan](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture/blob/main/docs/enterprisearchitecture/implementation-development/MICROSERVICES_TRANSFORMATION_PLAN.md)
- [Capability Map (PUML)](https://github.com/COPUR/fintechbankx-governance-architecture-enablement-enterprise-architecture/blob/main/docs/puml/service-mesh/enterprise-capability-map.puml)
- Repo dokümanları: [docs/README.md](docs/README.md).

## What this repository provides (Proposed)

Reusable AWS Terraform modules for FinTechBankX, aligned with the AWS Well-Architected pillars (reliability: three
AZs, NAT per AZ, Multi-AZ data stores; security: KMS everywhere, IRSA, least-privilege policies, TLS-only clients;
cost: Aurora Serverless v2, single NAT in dev, ECR lifecycle rules). Nothing here has been applied to an AWS account;
CI proves only that every module, example and stack validates.

| Path | Purpose |
|---|---|
| [modules/microservice-base](modules/microservice-base/README.md) | Per-service baseline (log group, SSM pointers, runtime secret, workload role, runtime access policy). Backward compatible with existing callers. |
| [modules/network-vpc](modules/network-vpc/README.md) | 3-AZ VPC with private/public/intra subnets, endpoints, flow logs |
| [modules/eks-cluster](modules/eks-cluster/README.md) | EKS with managed node groups, OIDC/IRSA, KMS, control-plane logs, add-ons |
| [modules/aurora-postgresql](modules/aurora-postgresql/README.md) | Service-owned Aurora PostgreSQL Serverless v2 (also used for Keycloak) |
| [modules/documentdb-cluster](modules/documentdb-cluster/README.md) | Service-owned Amazon DocumentDB (open finance data services) |
| [modules/elasticache-redis](modules/elasticache-redis/README.md) | Optional service-owned Redis with TLS and AUTH token |
| [modules/msk-cluster](modules/msk-cluster/README.md) | Amazon MSK with IAM auth and explicit topics |
| [modules/msk-client-access](modules/msk-client-access/README.md) | Topic-scoped MSK IAM policy per service |
| [modules/irsa-role](modules/irsa-role/README.md) | IAM role for one Kubernetes service account |
| [modules/external-secrets-irsa](modules/external-secrets-irsa/README.md) | IRSA role behind ClusterSecretStore `aws-secrets-manager` |
| [modules/ecr-repository](modules/ecr-repository/README.md) | Immutable, scanned, KMS-encrypted image repository |
| [modules/observability-amp](modules/observability-amp/README.md) | Amazon Managed Prometheus and optional Managed Grafana |
| [modules/github-oidc](modules/github-oidc/README.md) | GitHub Actions OIDC roles per service (push, deploy, plan, apply) |
| [stacks/platform](stacks/platform/README.md) | Per-environment composition root (dev, staging, prod) |
| `services/*` | Legacy open-finance baseline stacks from the monorepo (still validate; use `microservice-base`) |
| `examples/*`, `tests/consumer-compat/*` | Usage examples and the consumer contract fixture validated in CI |

### Consuming a module from a service repository

```hcl
module "service_base" {
  source = "git::https://github.com/COPUR/fintechbankx-platform-delivery-iac-terraform-modules.git//modules/microservice-base?ref=main"
  # pin a tag once one is released
}
```

### Validate locally

```bash
bash scripts/ci/terraform-validate-all.sh   # fmt -check, init -backend=false + validate everywhere, tfvars type-check
```

The same script runs in [.github/workflows/terraform.yml](.github/workflows/terraform.yml).

## Güvenlik ve Uyumluluk Notları
- Gerçek secret değerleri repo veya `.env` içinde tutulmaz.
- Secret üretim/rotasyon olayları merkezi log/SIEM'e taşınır.
- CI pipeline, anonimlik ve local-path sızıntısı kontrollerini bloklayıcı olarak çalıştırır.

## Katkı
- Katkı süreci için `CONTRIBUTING.md` ve squad runbook'ları izlenmelidir.
- PR'larda mimari kararlar ADR veya backlog referansı ile ilişkilendirilmelidir.

<!-- cell-architecture-start -->
## Cell-Based Architecture

This repository participates in the FinTechBankX cell-based resilience program.

- Plan: docs/architecture/CELL_BASED_ARCHITECTURE_IMPLEMENTATION_PLAN.md
- Backlog: docs/project-management/CELL_ARCHITECTURE_BACKLOG_BOARD.md
<!-- cell-architecture-end -->
