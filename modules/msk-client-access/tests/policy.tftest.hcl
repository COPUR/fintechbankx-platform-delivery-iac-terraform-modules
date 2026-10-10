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
