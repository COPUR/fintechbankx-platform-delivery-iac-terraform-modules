# Offline (mock provider): the JDBC URLs verify the Aurora server certificate
# (sslmode=verify-full) against the RDS CA bundle the platform publishes as
# ConfigMap rds-ca-bundle (key global-bundle.pem) and the service chart mounts
# at /etc/fintechbankx/rds-ca. sslmode=require encrypts but trusts any
# certificate (request-to-pay PR #14 review).

mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-000000000001"
    }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      endpoint        = "dev-request-to-pay.cluster-abc.me-central-1.rds.amazonaws.com"
      reader_endpoint = "dev-request-to-pay.cluster-ro-abc.me-central-1.rds.amazonaws.com"
      port            = 5432
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:me-central-1:111122223333:secret:rds-admin-AbCdEf"
        kms_key_id    = "arn:aws:kms:me-central-1:111122223333:key/00000000-0000-4000-8000-000000000001"
        secret_status = "active"
      }]
    }
  }
}

variables {
  name                       = "dev-payment-request-to-pay-service"
  database_name              = "db_pay_request_to_pay_dev"
  master_username            = "rtp_admin"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0aaaaaaaaaaaaaaa1", "subnet-0aaaaaaaaaaaaaaa2"]
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  app_secret_name            = "dev/payment-request-to-pay-service/db-app"
}

run "jdbc_urls_verify_the_server_certificate" {
  command = apply

  assert {
    condition     = output.jdbc_url == "jdbc:postgresql://dev-request-to-pay.cluster-abc.me-central-1.rds.amazonaws.com:5432/db_pay_request_to_pay_dev?sslmode=verify-full&sslrootcert=/etc/fintechbankx/rds-ca/global-bundle.pem"
    error_message = "jdbc_url must use sslmode=verify-full with the mounted RDS CA bundle."
  }

  assert {
    condition     = output.reader_jdbc_url == "jdbc:postgresql://dev-request-to-pay.cluster-ro-abc.me-central-1.rds.amazonaws.com:5432/db_pay_request_to_pay_dev?sslmode=verify-full&sslrootcert=/etc/fintechbankx/rds-ca/global-bundle.pem"
    error_message = "reader_jdbc_url must use the reader endpoint with sslmode=verify-full."
  }

  assert {
    condition     = output.ssl_root_cert_path == "/etc/fintechbankx/rds-ca/global-bundle.pem"
    error_message = "ssl_root_cert_path must default to the chart's mount of ConfigMap rds-ca-bundle."
  }
}

run "no_url_without_certificate_verification" {
  command = apply

  assert {
    condition     = !strcontains(output.jdbc_url, "sslmode=require") && !strcontains(output.reader_jdbc_url, "sslmode=require")
    error_message = "sslmode=require does not verify the server certificate."
  }
}

run "ssl_root_cert_path_must_be_an_absolute_pem_path" {
  command = plan

  variables {
    ssl_root_cert_path = "global-bundle.pem"
  }

  expect_failures = [var.ssl_root_cert_path]
}
