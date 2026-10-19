# Where the pre-production gate for the pgaudit bypass is recorded (README
# "Audit logging", compensating control): input pgaudit_bypass_gate. A cluster
# counts as non-production only when it carries at least one environment
# marker (tag Environment, a dev-/staging-/prod- name prefix, a
# _dev/_staging/_prod database_name suffix) and every marker it carries is dev
# or staging. Every other cluster is treated as production, and the plan is
# refused until pgaudit_bypass_gate holds the gate record: the option and the
# link or id of the recorded drill run. Activity Streams is refused as an
# option: AWS documents that Aurora Serverless v2 does not support database
# activity streams, and this module creates only db.serverless instances.

mock_provider "aws" {}

variables {
  name                       = "dev-payment-request-to-pay-service"
  database_name              = "db_pay_request_to_pay_dev"
  master_username            = "rtp_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/payment-request-to-pay-service/db-app"
}

run "dev_cluster_plans_without_record" {
  command = plan

  assert {
    condition     = var.pgaudit_bypass_gate == null && aws_rds_cluster.this.cluster_identifier == "dev-payment-request-to-pay-service-aurora"
    error_message = "A cluster named dev-<slug> with a _dev database is non-production and plans without a gate record."
  }

  assert {
    condition     = output.pgaudit_bypass_gate_required == false
    error_message = "Output pgaudit_bypass_gate_required is false for a non-production cluster."
  }
}

# Platform stack shape: name <prefix>-<env>-grafana (no env prefix), database
# "grafana" (no env suffix), tag Environment from the stack.
run "staging_tag_alone_marks_non_production" {
  command = plan

  variables {
    name            = "fintechbankx-staging-grafana"
    database_name   = "grafana"
    app_secret_name = "staging/observability/grafana-db"
    tags            = { Environment = "staging" }
  }

  assert {
    condition     = aws_rds_cluster.this.cluster_identifier == "fintechbankx-staging-grafana-aurora"
    error_message = "Tag Environment = staging marks the cluster non-production; it plans without a gate record."
  }
}

run "production_name_refused_without_record" {
  command = plan

  variables {
    name            = "prod-payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay_prod"
    app_secret_name = "prod/payment-request-to-pay-service/db-app"
  }

  expect_failures = [aws_rds_cluster.this]
}

run "production_tag_refused_without_record" {
  command = plan

  variables {
    name            = "fintechbankx-prod-grafana"
    database_name   = "grafana"
    app_secret_name = "prod/observability/grafana-db"
    tags            = { Environment = "prod" }
  }

  expect_failures = [aws_rds_cluster.this]
}

# A prod marker wins over dev markers: any marker that is not dev or staging
# makes the cluster production.
run "mixed_markers_count_as_production" {
  command = plan

  variables {
    tags = { Environment = "prod" }
  }

  expect_failures = [aws_rds_cluster.this]
}

# Each marker source counts on its own: a staging- name prefix with no other
# marker, and a _staging database_name suffix with no other marker, each mark
# the cluster non-production. Without these runs, dropping the database_name
# marker, or staging from either regex, left every run passing.
run "name_prefix_alone_marks_non_production" {
  command = plan

  variables {
    name            = "staging-payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay"
    app_secret_name = "staging/payment-request-to-pay-service/db-app"
  }

  assert {
    condition     = output.pgaudit_bypass_gate_required == false
    error_message = "A staging- name prefix alone marks the cluster non-production; it plans without a gate record."
  }
}

run "database_name_suffix_alone_marks_non_production" {
  command = plan

  variables {
    name            = "payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay_staging"
    app_secret_name = "staging/payment-request-to-pay-service/db-app"
  }

  assert {
    condition     = output.pgaudit_bypass_gate_required == false
    error_message = "A _staging database_name suffix alone marks the cluster non-production; it plans without a gate record."
  }
}

# A prod marker from the name or from the database_name wins over a dev tag,
# as a prod tag wins over dev name and database markers
# (mixed_markers_count_as_production). Without these runs, dropping prod from
# the name or database_name regex left every run passing while such a cluster
# planned without a record.
run "prod_name_prefix_next_to_dev_tag_refused" {
  command = plan

  variables {
    name            = "prod-payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay"
    app_secret_name = "prod/payment-request-to-pay-service/db-app"
    tags            = { Environment = "dev" }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "prod_database_name_suffix_next_to_dev_tag_refused" {
  command = plan

  variables {
    name            = "payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay_prod"
    app_secret_name = "prod/payment-request-to-pay-service/db-app"
    tags            = { Environment = "dev" }
  }

  expect_failures = [aws_rds_cluster.this]
}

# Fail closed: no marker at all is production.
run "unmarked_cluster_refused_without_record" {
  command = plan

  variables {
    name            = "payment-request-to-pay-service"
    database_name   = "db_pay_request_to_pay"
    app_secret_name = "x/payment-request-to-pay-service/db-app"
  }

  expect_failures = [aws_rds_cluster.this]
}

# Fail closed: a marker that is not exactly dev or staging is production.
run "unknown_environment_tag_refused_without_record" {
  command = plan

  variables {
    tags = { Environment = "Dev" }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "production_plans_with_break_glass_record" {
  command = plan

  variables {
    name                = "prod-payment-request-to-pay-service"
    database_name       = "db_pay_request_to_pay_prod"
    app_secret_name     = "prod/payment-request-to-pay-service/db-app"
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "https://tickets.example.com/browse/CHG-1042" }
  }

  assert {
    condition     = aws_rds_cluster.this.cluster_identifier == "prod-payment-request-to-pay-service-aurora"
    error_message = "A production cluster plans once pgaudit_bypass_gate holds the break-glass record."
  }

  assert {
    condition     = output.pgaudit_bypass_gate_required == true
    error_message = "Output pgaudit_bypass_gate_required is true for a cluster that counts as production."
  }
}

run "record_accepts_ticket_and_issue_ids" {
  command = plan

  variables {
    name                = "prod-payment-request-to-pay-service"
    database_name       = "db_pay_request_to_pay_prod"
    app_secret_name     = "prod/payment-request-to-pay-service/db-app"
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "example-org/platform-change-records#17" }
  }

  assert {
    condition     = var.pgaudit_bypass_gate.drill_run == "example-org/platform-change-records#17"
    error_message = "drill_run accepts an <owner>/<repo>#<number> issue id."
  }
}

run "activity_streams_refused_on_serverless" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "activity-streams", drill_run = "CHG-1042" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

run "unknown_option_refused" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "none", drill_run = "CHG-1042" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

run "placeholder_drill_run_refused" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "<drill run>" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

run "tbd_drill_run_refused" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "TBD" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

# drill_run is checked for form only. An https link needs a host with a dot
# and a path: "https://TBD" (no dotted host) and a bare host with no path are
# refused, as "<drill run>" and "TBD" are above. A well-formed link or id that
# names no drill run still passes; the reviewer of the plan checks the record.
run "https_drill_run_without_dotted_host_refused" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "https://TBD" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

run "https_drill_run_without_path_refused" {
  command = plan

  variables {
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "https://tickets.example.com/" }
  }

  expect_failures = [var.pgaudit_bypass_gate]
}

run "record_accepts_link_with_port" {
  command = plan

  variables {
    name                = "prod-payment-request-to-pay-service"
    database_name       = "db_pay_request_to_pay_prod"
    app_secret_name     = "prod/payment-request-to-pay-service/db-app"
    pgaudit_bypass_gate = { option = "break-glass", drill_run = "https://tickets.example.com:8443/browse/CHG-1042" }
  }

  assert {
    condition     = output.pgaudit_bypass_gate_required == true
    error_message = "drill_run accepts an https link with a dotted host, a port and a path."
  }
}
