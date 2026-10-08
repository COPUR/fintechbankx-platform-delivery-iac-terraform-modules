terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}

provider "aws" {
  region = "me-central-1"
}

# Illustrative: svc-ln-loan-lifecycle produces evt.ln.loan.*, consumes risk
# decisions and settled payments, and may redrive to the payments DLQ. Real
# inputs come from topics/generated/msk-client-access.json in
# fintechbankx-platform-event-streaming-kafka.
module "loan_msk_access" {
  source = "../../modules/msk-client-access"

  service_id                = "svc-ln-loan-lifecycle"
  policy_name               = "dev-loan-lifecycle-service-msk"
  cluster_arn               = "arn:aws:kafka:me-central-1:111122223333:cluster/fintechbankx-dev-events/0b1c2d3e-1111-2222-3333-444455556666-3"
  produce_topic_prefixes    = ["evt.ln.loan."]
  produce_topics            = ["evt.pay.payment.dlq.v1"]
  consume_topics            = ["evt.rsk.decision.*", "evt.pay.payment.settled.v1"]
  consumer_groups           = ["cg.svc-ln-loan-lifecycle.payment-settled.v1"]
  transactional_id_prefixes = ["svc-ln-loan-lifecycle"]
  attach_to_role_names      = ["dev-loan-lifecycle-service-irsa"]
}

output "policy_json" {
  value = module.loan_msk_access.policy_json
}
