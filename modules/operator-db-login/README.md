# operator-db-login

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

Personal database logins for the operators of one service database, through IAM database authentication. Each
person connects as their own login, so `session_user`, pgaudit and anything a service records from them (for
example the accounts ledger's outbox discard audit) name the person, not a shared role.

## What it creates

- AWS side: one customer managed policy, `<env>-<slug>-db-operator-login`, with one statement per operator:
  `rds-db:connect` on `dbuser:<cluster resource id>/<their login>` only, with the condition
  `aws:userid` like `*:<their Identity Center user name>`. A permission-set session's `aws:userid` is
  `<role id>:<user name>`, a session name IAM Identity Center sets and the person cannot choose, so nobody can
  connect as somebody else's login. The module creates no permission set: the account-baseline owner adds the
  policy to the operators' permission set as a customer managed policy reference (name, path `/`).
- Database side: the output `login_sql`, the desired state for the DBA to run as the cluster's master user. It
  keeps the NOLOGIN group `operator_group_role` and one LOGIN role per operator (`op_<name>`, member of the group
  and of `rds_iam`, no password, no role attributes, no other membership, owns nothing, nobody inherits it, and
  `idle_in_transaction_session_timeout` set, so a transaction left open at the prompt ends instead of holding rows
  the service's own jobs wait for, such as the outbox relay's discard step). A
  member of the group that is no longer listed is taken out; an `op_` login that is no longer listed also loses
  LOGIN. Roles are kept, not dropped, so names in audit rows keep pointing at the same person. The service's own
  users (`reserved_db_users`) can never be the group or a login, and the SQL stops instead of continuing when it
  finds a membership it cannot revoke, a group that inherits another role, or an existing role it would take
  over that is more than an operator login.

What the group may do inside the service's schema is granted by the service's own migration (the schema owner
grants on its tables), never by this module.

## Order

1. Apply the stack that calls this module (creates the policy).
2. The account-baseline owner adds `policy_name` to the operators' permission set.
3. The DBA runs `login_sql` as the master user in `database_name`:
   `terraform output -raw <module>_login_sql > login.sql`, then
   `psql "<master connection>" -v ON_ERROR_STOP=1 --single-transaction -f login.sql`.
4. Deploy the service release whose migration grants the group (it fails closed while the group is missing).

To remove a person: delete their entry, apply, and run the new `login_sql`.

## Connecting

From the operator host (`operator-access`), or through an SSM port-forwarding session to it, with the person's own
Identity Center credentials:

```bash
aws rds generate-db-auth-token --hostname "<cluster writer endpoint>" --port 5432 \
  --region "<region>" --username op_<name>
psql "host=<cluster writer endpoint> port=5432 dbname=<database_name> user=op_<name> sslmode=verify-full sslrootcert=<rds-ca bundle>"
```

At psql's prompt, paste the token. It is valid for 15 minutes and is never stored. The service database's security group must admit the
operator host (`operator-access` output `operator_security_group_id`).

## Residual risk

- `rds-db:connect` is authorised when the connection is made and is not recorded in CloudTrail; the database's
  own log (pgaudit, connection logging) is the record and names the login.
- The binding to the person relies on the policy being attached only to the Identity Center permission set. A
  role whose callers choose their own session name must never get it.
- Anyone with the master user (or the schema owner) can still act in the database under that shared name; their
  use is for the DBA process, not for operator tasks.
- `idle_in_transaction_session_timeout` is a session default: an operator can change it with `SET` in their own
  session. It stops a transaction forgotten at the prompt, not one an operator keeps open on purpose; the
  database's log shows such a session, and `pg_terminate_backend` by the DBA ends it.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | `dev`, `staging` or `prod`. |
| `service_slug` | `string` | required | Service slug; part of the policy name. |
| `database_name` | `string` | required | The service database; the SQL refuses any other. |
| `cluster_resource_id` | `string` | required | Aurora `cluster_resource_id` (`cluster-<ID>`), not the cluster identifier. |
| `operator_group_role` | `string` | required | NOLOGIN group of the logins; not `pg_*`, `rds_*`, `op_*`, `postgres` or `rdsadmin`. |
| `operators` | `map(string)` | required | Identity Center user name => login `op_<name>`; 1 to 20, one login per person, no `*` or `?`. |
| `reserved_db_users` | `list(string)` | required | The service's master, runtime and migration users. |
| `connection_limit` | `number` | `2` | Sessions per login, 1..10. |
| `idle_in_transaction_timeout_seconds` | `number` | `60` | `idle_in_transaction_session_timeout` of each login, 5..600 s. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|---|---|
| `policy_arn` | The connect policy. |
| `policy_name` | Name for the permission set's customer managed policy reference. |
| `operator_logins` | User name => login. |
| `operator_group_role` | The group the service's migration grants. |
| `login_sql` | Desired-state SQL for the DBA (holds no secret). |
