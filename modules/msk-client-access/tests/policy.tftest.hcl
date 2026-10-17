# Offline (mock provider): topic-scoped grants, consumer-group ownership, wildcard rejection.

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
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}


variables {
  service_id             = "svc-ln-loan-lifecycle"
  policy_name            = "dev-loan-lifecycle-service-msk"
  cluster_arn            = "arn:aws:kafka:me-central-1:111122223333:cluster/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3"
  produce_topic_prefixes = ["evt.ln.loan."]
  consume_topics         = ["evt.pay.payment.settled.v1"]
  consumer_groups        = ["cg.svc-ln-loan-lifecycle.payment-settled.v1"]
}

run "grants_own_prefix_and_groups_only" {
  command = plan

  assert {
    condition     = local.produce_arns == ["arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.ln.loan.*"]
    error_message = "Produce grant must be the own prefix only."
  }

  assert {
    condition     = local.group_arns == ["arn:aws:kafka:me-central-1:111122223333:group/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/cg.svc-ln-loan-lifecycle.payment-settled.v1"]
    error_message = "Group grant must be the declared group only."
  }

  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.this.statement :
      length(setintersection(s.actions, ["kafka-cluster:CreateTopic", "kafka-cluster:AlterTopic", "kafka-cluster:DeleteTopic"])) == 0
    ])
    error_message = "Services must never get topic administration."
  }
}

run "foreign_consumer_group_prefix_rejected" {
  command = plan

  variables {
    consumer_groups         = []
    consumer_group_prefixes = ["cg.svc-pay-initiation-settlement."]
  }

  expect_failures = [aws_iam_policy.this]
}

run "consumer_without_group_rejected" {
  command = plan

  variables {
    consumer_groups = []
  }

  expect_failures = [aws_iam_policy.this]
}

run "wildcard_produce_prefix_rejected" {
  command = plan

  variables {
    produce_topic_prefixes = ["evt.*"]
  }

  expect_failures = [var.produce_topic_prefixes]
}

run "wildcard_exact_produce_topic_rejected" {
  command = plan

  variables {
    produce_topics = ["evt.ln.loan.*"]
  }

  expect_failures = [var.produce_topics]
}

# ADR-019 (event-streaming repository): one topic per aggregate,
# evt.<ctx>.<aggregate>.v<major>, plus consumer-owned DLQs
# evt.<ctx>.<aggregate>.dlq.v<major>. The runs below pass the services' rows of
# topics/generated/msk-client-access.json unchanged.

# Producer only: the accounts ledger writes evt.acc.account.v1 and consumes
# nothing.
run "catalog_row_of_a_producer_only_service" {
  command = plan

  variables {
    service_id             = "svc-acc-accounts-ledger"
    policy_name            = "dev-accounts-ledger-service-msk"
    produce_topics         = ["evt.acc.account.v1"]
    produce_topic_prefixes = ["evt.acc.account."]
    consume_topics         = []
    consumer_groups        = []
    attach_to_role_names   = ["dev-accounts-ledger-service-irsa"]
  }

  assert {
    condition = local.produce_arns == [
      "arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.acc.account.*",
      "arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.acc.account.v1",
    ]
    error_message = "The ledger may write its own aggregate namespace and its aggregate topic, nothing else."
  }

  assert {
    condition     = length(local.consume_arns) == 0 && length(local.group_arns) == 0 && length(local.txn_arns) == 0
    error_message = "A producer-only service gets no read, consumer-group or transactional-id grant."
  }

  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.this.statement :
      length(setintersection(s.actions, ["kafka-cluster:CreateTopic", "kafka-cluster:AlterTopic", "kafka-cluster:DeleteTopic", "kafka-cluster:ReadData"])) == 0
    ])
    error_message = "The ledger gets neither topic administration nor reads."
  }
}

# The narrow form: only the exact aggregate topic, no namespace prefix (the
# grant the ledger's own deploy/terraform gives its pods today).
run "exact_aggregate_topic_without_prefix" {
  command = plan

  variables {
    service_id             = "svc-acc-accounts-ledger"
    policy_name            = "dev-accounts-ledger-service-msk"
    produce_topics         = ["evt.acc.account.v1"]
    produce_topic_prefixes = []
    consume_topics         = []
    consumer_groups        = []
  }

  assert {
    condition     = local.produce_arns == ["arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.acc.account.v1"]
    error_message = "produce_topics grants exactly the listed aggregate topic."
  }
}

# Consumer: a whole aggregate topic and the consumer's own DLQ (redrive), as
# a future reader of evt.acc.account.v1 would list it.
run "catalog_row_of_a_consumer" {
  command = plan

  variables {
    produce_topics          = ["evt.ln.loan.dlq.v1", "evt.ln.loan.v1"]
    produce_topic_prefixes  = ["evt.ln.loan."]
    consume_topics          = ["evt.ln.loan.dlq.v1", "evt.pay.payment.v1"]
    consumer_groups         = ["cg.svc-ln-loan-lifecycle.loan-repayment-allocation.v1"]
    consumer_group_prefixes = ["cg.svc-ln-loan-lifecycle."]
  }

  assert {
    condition = local.consume_arns == [
      "arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.ln.loan.dlq.v1",
      "arn:aws:kafka:me-central-1:111122223333:topic/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3/evt.pay.payment.v1",
    ]
    error_message = "Consumers read exactly the listed aggregate topics and their own DLQ."
  }
}

run "aggregate_topic_without_major_rejected" {
  command = plan

  variables {
    produce_topics = ["evt.acc.account"]
  }

  expect_failures = [var.produce_topics]
}

run "wildcard_major_consume_topic_rejected" {
  command = plan

  variables {
    consume_topics = ["evt.acc.account.v*"]
  }

  expect_failures = [var.consume_topics]
}
