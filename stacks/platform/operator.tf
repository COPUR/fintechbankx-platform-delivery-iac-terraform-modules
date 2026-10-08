# Operator access (Proposed): an in-VPC host reachable through SSM Session
# Manager only, and per-service roles that may read only
# <env>/<slug>/db-import. Off by default; enable per environment. Identity
# Center permission sets are managed outside this stack: pass the role ARNs
# their assignments create in operator_principal_arns.

module "operator_access" {
  source = "../../modules/operator-access"
  count  = var.operator_access_enabled ? 1 : 0

  name               = local.name
  vpc_id             = module.network.vpc_id
  subnet_id          = module.network.private_subnet_ids[0]
  egress_cidr_blocks = [var.vpc_cidr]
  tags               = local.tags
}

module "operator_db_access" {
  source = "../../modules/operator-db-access"
  count  = var.operator_access_enabled && length(var.operator_db_import_service_slugs) > 0 ? 1 : 0

  environment            = var.environment
  service_slugs          = var.operator_db_import_service_slugs
  trusted_principal_arns = var.operator_principal_arns
  tags                   = local.tags
}
