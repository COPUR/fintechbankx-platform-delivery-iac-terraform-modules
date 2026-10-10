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

module "amp" {
  source = "../../modules/observability-amp"

  name           = "fintechbankx-dev"
  enable_grafana = true
  rule_group_namespaces = {
    fintechbankx-slo = <<-YAML
      groups:
        - name: fintechbankx-http
          rules:
            - record: service:http_server_requests_seconds_count:rate5m
              expr: sum by (application) (rate(http_server_requests_seconds_count[5m]))
    YAML
  }
}

output "remote_write_url" {
  value = module.amp.remote_write_url
}
