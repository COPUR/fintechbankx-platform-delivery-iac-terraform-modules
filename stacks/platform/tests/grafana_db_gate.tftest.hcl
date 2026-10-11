# Offline (mock providers, no credentials): the Grafana database is an
# aurora-postgresql cluster, so in prod its plan is refused until the
# pre-production gate for the pgaudit bypass is recorded (module input
# pgaudit_bypass_gate, stack input grafana_database_pgaudit_bypass_gate; module
# README "Audit logging", compensating control). The stack tags it
# Environment = <environment>, which is the module's environment marker.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "me-central-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["me-central-1a", "me-central-1b", "me-central-1c"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0", insecure_value = "ami-0123456789abcdef0" }
  }
}

mock_provider "tls" {}

# Known policy JSON for the observability IRSA roles (bucket ARNs are unknown
# at plan and modules/irsa-role counts on the JSON).
override_data {
  target = data.aws_iam_policy_document.obs_storage["tempo"]
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

override_data {
  target = data.aws_iam_policy_document.obs_storage["loki"]
  values = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
}

variables {
  vpc_cidr                             = "10.42.0.0/16"
  verify_terraform_state_bucket_policy = false
  github_services                      = {}
  create_grafana_database              = true
}

run "dev_grafana_db_plans_without_gate_record" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = module.grafana_db[0].cluster_identifier == "fintechbankx-dev-grafana-aurora" && !module.grafana_db[0].pgaudit_bypass_gate_required
    error_message = "dev is marked non-production (tag Environment = dev); the Grafana database plans without a gate record."
  }
}

# Without the record the prod plan is refused by the module's precondition
# (modules/aurora-postgresql/tests/pgaudit_bypass_gate.tftest.hcl); a test
# run cannot expect a failure inside a child module, so this run checks the
# other half: the stack's prod cluster counts as production and plans once the
# stack input carries the record.
run "prod_grafana_db_plans_with_gate_record" {
  command = plan

  variables {
    environment                          = "prod"
    grafana_database_pgaudit_bypass_gate = { option = "break-glass", drill_run = "https://tickets.example.com/browse/CHG-1042" }
  }

  assert {
    condition     = module.grafana_db[0].cluster_identifier == "fintechbankx-prod-grafana-aurora" && module.grafana_db[0].pgaudit_bypass_gate_required
    error_message = "The prod Grafana database counts as production (tag Environment = prod) and plans once grafana_database_pgaudit_bypass_gate holds the record."
  }
}
