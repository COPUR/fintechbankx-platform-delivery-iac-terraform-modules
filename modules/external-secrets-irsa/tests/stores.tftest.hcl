# Offline (mock provider): two read-only External Secrets roles. The service
# store role reads <env>/* except platform and identity secrets; the platform
# store role reads only platform, identity and oidc-client secrets.

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
  cluster_name      = "fintechbankx-prod"
  environment       = "prod"
  oidc_provider_arn = "arn:aws:iam::111122223333:oidc-provider/oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
  oidc_provider_url = "https://oidc.eks.me-central-1.amazonaws.com/id/EXAMPLE"
}

run "service_and_platform_stores" {
  command = plan

  assert {
    condition = (
      local.store_roles["service"].service_account == "external-secrets" &&
      local.store_roles["platform"].service_account == "external-secrets-platform" &&
      local.store_roles["service"].namespace == "external-secrets" &&
      local.store_roles["platform"].namespace == "external-secrets"
    )
    error_message = "Service store trusts external-secrets/external-secrets; platform store trusts external-secrets/external-secrets-platform."
  }

  assert {
    condition = toset(flatten([
      for st in data.aws_iam_policy_document.service_store.statement : tolist(st.resources) if st.effect != "Deny" && contains(tolist(st.actions), "secretsmanager:GetSecretValue")
    ])) == toset(["arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/*"])
    error_message = "Service store reads prod/*."
  }

  assert {
    condition = toset(flatten([
      for st in data.aws_iam_policy_document.service_store.statement : tolist(st.resources) if st.effect == "Deny" && st.sid == "DenyPlatformAndIdentitySecrets"
      ])) == toset([
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/platform/*",
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/identity-keycloak/*",
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/identity-openldap/*",
    ])
    error_message = "Service store must explicitly deny platform and identity secrets."
  }

  assert {
    condition = toset(flatten([
      for st in data.aws_iam_policy_document.platform_store.statement : tolist(st.resources) if st.effect != "Deny" && contains(tolist(st.actions), "secretsmanager:GetSecretValue")
      ])) == toset([
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/platform/*",
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/identity-keycloak/*",
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/identity-openldap/*",
      "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/*/oidc-client-??????",
    ])
    error_message = "Platform store reads only platform, identity and oidc-client secrets."
  }

  # Read-only: Secrets Manager reads and KMS decrypt via Secrets Manager on tagged keys only.
  assert {
    condition = alltrue(flatten([
      for doc in [data.aws_iam_policy_document.service_store, data.aws_iam_policy_document.platform_store] : [
        for st in doc.statement : [
          for a in st.actions : contains(["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret", "kms:Decrypt"], a)
        ] if st.effect != "Deny"
      ]
    ]))
    error_message = "Both store roles are read-only (GetSecretValue, DescribeSecret, kms:Decrypt)."
  }

  assert {
    condition = alltrue([
      for doc in [data.aws_iam_policy_document.service_store, data.aws_iam_policy_document.platform_store] : alltrue([
        for st in doc.statement :
        toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "kms:ViaService"])) == toset(["secretsmanager.me-central-1.amazonaws.com"]) &&
        toset(flatten([for c in st.condition : tolist(c.values) if c.variable == "aws:ResourceTag/fintechbankx.io/secrets"])) == toset(["true"])
        if contains(tolist(st.actions), "kms:Decrypt")
      ])
    ])
    error_message = "kms:Decrypt only via Secrets Manager on keys tagged fintechbankx.io/secrets=true."
  }
}

# Operator db-import credentials (<env>/<slug>/db-import, operator-db-access)
# sit inside the service store's <env>/* read and are encrypted with the
# tagged secrets key; an explicit Deny keeps both stores from reading or
# decrypting them (Deny wins over any Allow, including <env>/*).
run "db_import_secrets_denied_to_both_stores" {
  command = plan

  assert {
    condition = alltrue([
      for doc in [data.aws_iam_policy_document.service_store, data.aws_iam_policy_document.platform_store] :
      length([
        for st in doc.statement : st if st.effect == "Deny" &&
        toset(st.actions) == toset(["secretsmanager:*"]) &&
        toset(st.resources) == toset(["arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/*/db-import-??????"])
      ]) == 1
    ])
    error_message = "Both store roles must explicitly deny secretsmanager:* on <env>/*/db-import-??????."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.service_store.statement : st
      if st.effect != "Deny" && contains(tolist(st.resources), "arn:aws:secretsmanager:me-central-1:111122223333:secret:prod/*")
    ]) == 1
    error_message = "The Deny is needed because the service store still reads <env>/*."
  }
}
