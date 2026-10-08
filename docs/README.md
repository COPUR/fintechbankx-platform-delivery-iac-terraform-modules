# Documentation

Service-level architecture, contracts, and test references for `fintechbankx-platform-delivery-iac-terraform-modules`.

- [Repository overview and module index](../README.md)
- [Platform stack (per-environment composition)](../stacks/platform/README.md)
- [microservice-base compatibility notes](../modules/microservice-base/README.md)
- [Cell-based architecture plan](architecture/CELL_BASED_ARCHITECTURE_IMPLEMENTATION_PLAN.md)
- [Cell architecture backlog](project-management/CELL_ARCHITECTURE_BACKLOG_BOARD.md)
- [Publication Guardrails](publication/PUBLICATION_GUARDRAILS.md)

## Validation evidence

CI (`.github/workflows/terraform.yml`) runs `scripts/ci/terraform-validate-all.sh`: `terraform fmt -check`,
`terraform init -backend=false` plus `terraform validate` for every module, example, stack, legacy service stack and
consumer fixture, and a type-check of `stacks/platform/environments/*.tfvars.example`. No `plan` or `apply` runs in
CI; nothing in this repository is deployed.
