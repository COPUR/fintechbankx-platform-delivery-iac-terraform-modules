# Operator access (Proposed): an in-VPC host reachable through SSM Session
# Manager only, and per-service roles that may read only
# <env>/<slug>/db-import. Off by default; enable per environment. Identity
# Center permission sets are managed outside this stack: pass the role ARNs
# their assignments create in operator_principal_arns.
#
# Credential path (README "Operator database access"): the workstation
# assumes <env>-<slug>-db-import with a source identity, reads the db-import
# secret into the psql process and connects through an SSM port-forwarding
# session via the host; TLS runs end to end from the workstation to Aurora,
# so the password never lands on the host. With operator access on, the VPC
# gets the ssmmessages, ec2messages and kms endpoints (main.tf), and session
# logs go to a KMS-encrypted CloudWatch log group.

module "operator_access" {
  source = "../../modules/operator-access"
  count  = var.operator_access_enabled ? 1 : 0

  name               = local.name
  vpc_id             = module.network.vpc_id
  subnet_id          = module.network.private_subnet_ids[0]
  egress_cidr_blocks = [var.vpc_cidr]

  session_log_retention_days         = var.operator_session_log_retention_days
  manage_session_manager_preferences = var.manage_session_manager_preferences
  tags                               = local.tags
}

module "operator_db_access" {
  source = "../../modules/operator-db-access"
  count  = var.operator_access_enabled && length(var.operator_db_import_service_slugs) > 0 ? 1 : 0

  environment            = var.environment
  service_slugs          = var.operator_db_import_service_slugs
  trusted_principal_arns = var.operator_principal_arns
  # ADR-023 secrets key of each service database (never its storage key).
  kms_key_arns = var.operator_db_import_kms_key_arns
  tags         = local.tags
}
