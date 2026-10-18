# operator-db-login

Status: **Proposed** (validated with `terraform validate` and `terraform test`; not applied anywhere).

Personal database logins for the operators of one service database, through IAM database authentication. Each
person gets their own login, so `session_user`, pgaudit and anything a service records from them (for example the
accounts ledger's outbox discard audit) name that login, not a shared role. The module binds each login to one
Identity Center user name; "Residual risk" lists who can still act as a login.

## What it creates

- AWS side: one customer managed policy, `<env>-<slug>-db-operator-login` (`-db-readonly-login` in read-only
  mode), with one statement per operator:
  `rds-db:connect` on `dbuser:<cluster resource id>/<their login>` only, with the condition
  `aws:userid` like `*:<their Identity Center user name>`. A permission-set session's `aws:userid` is
  `<role id>:<user name>`, and Identity Center sets that session name. The policy only adds an allow: it does not
  stop anyone else who may connect (see "Residual risk"). The module creates no permission set: the
  account-baseline owner adds the policy to the operators' permission set as a customer managed policy reference
  (name, path `/`). The plan fails when the policy would be larger than IAM's 6,144 characters (counted without
  whitespace).
- Database side: the output `login_sql`, the desired state for the DBA to run as the cluster's master user. It
  needs PostgreSQL 16 or later, `rds_iam` and a loaded pgaudit, and runs only in `database_name`. It keeps:
  - the NOLOGIN group `operator_group_role`, with no role attributes, member of no role, and `CONNECT` on
    `database_name`. When the SQL creates the group it marks it with the comment
    `operator-db-login group <env>/<slug>`, or `operator-db-login group <env>/<slug> read-only` in read-only
    mode. The mark names the mode, so an operator instance and a read-only instance never share a group;
  - one login per operator (`op_<name>`), marked with the comment `operator-db-login <group>: <Identity Center
    user name>` when the SQL creates it. Each login is a member of the group and of `rds_iam`, both with INHERIT
    and without SET or ADMIN, granted by the master user. So a login uses what the group and `rds_iam` may do,
    but cannot `SET ROLE` to either of them, and cannot make objects that they own. It has no other membership,
    no role attributes, nobody else is a member of it, it owns nothing and holds no privilege of its own in any
    database.
- The run turns `createrole_self_grant` off (`SET LOCAL`), so the master gets no membership of its own in the
  roles the SQL creates, even when the master's own default sets that option. The master keeps only the ADMIN row
  PostgreSQL 16 adds on every role a CREATEROLE user creates.
- Every run sets these again on each listed login: LOGIN (operator mode), INHERIT, `CONNECTION LIMIT
  connection_limit`, `PASSWORD NULL`, membership of `rds_iam` and of the group, and three role-wide settings:
  - `idle_in_transaction_session_timeout` (`idle_in_transaction_timeout_seconds`), so a transaction left open at
    the prompt ends instead of holding rows the service's own jobs wait for, such as the outbox relay's discard
    step;
  - `pgaudit.log = 'read,write,ddl,role'`, so pgaudit logs, under the login's name, every `SELECT` and `COPY`
    from a table (read), every `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` and `COPY` into one (write), every schema
    change (ddl) and every `GRANT`, `REVOKE` and `CREATE`, `ALTER` or `DROP ROLE` (role). The log has the
    statement text, so it can hold personal data from the statement;
  - `default_transaction_read_only = on` in read-only mode; operator mode resets it.
- A login that is no longer listed but carries this group's mark is retired, whether or not it is still in the
  group: it loses LOGIN, `rds_iam` and the group, and its mark gets ` (retired)` at the end. Roles are kept, not
  dropped, and a retired login is never enabled again: a person who comes back gets a new login name.

What the group may do inside the service's schema is granted by the service's own migration (the schema owner
grants on its tables), never by this module.

### When the SQL stops

The SQL adopts only roles that carry its mark, and stops instead of repairing anything that would destroy
evidence. It stops, with a message naming what it found, when:

- the server is older than PostgreSQL 16, the database is not `database_name`, or `rds_iam` is missing;
- pgaudit is not loaded (`pgaudit.log` is not in `pg_settings`). The message names the fix: add pgaudit to
  `shared_preload_libraries` in the cluster parameter group (`aurora-postgresql` `pgaudit_enabled = true`), reboot
  the instances, and run the SQL again;
- the group or a login is one of the service's own users (`reserved_db_users`);
- the group exists without this instance's mark (a role the module did not create, or the group of an instance
  of the other mode), has a role attribute, is a member of any role, or owns a large object;
- the group has a member other than this group's marked logins, granted by the master with INHERIT and without
  SET or ADMIN. That covers a service user, a role the module did not create, a grant from another grantor and a
  grant with SET or ADMIN. The only other row allowed is the ADMIN row PostgreSQL 16 adds for the master on every
  role it creates (granted by the bootstrap superuser, no INHERIT, no SET). The SQL adds no other row itself,
  because it turns `createrole_self_grant` off;
- a listed login exists without a mark, with a mark of another group, with the mark of another user name, or
  marked retired;
- a listed login was changed outside this SQL: it has a role attribute, is not in `rds_iam`, has `rds_iam` with
  SET or ADMIN, cannot log in (operator mode), is not in the group, is a member of any other role, can `SET ROLE`
  to or grant any other role (for example through an ADMIN that `rds_iam` was given, which every login
  inherits), has a member (other than the master's automatic ADMIN row), has a setting for one database
  (`ALTER ROLE ... IN DATABASE ... SET`), has a role-wide setting other than the three above, or owns an object,
  holds a privilege or is named by a policy in any database of the cluster (tables, columns, schemas, databases,
  functions, large objects and default privileges included);
- a login it retires is in `rds_iam` through a grant that neither the master nor a role whose privileges the
  master has (such as `rds_superuser`, when that role holds ADMIN on `rds_iam`) made, so the master cannot revoke
  it;
- in read-only mode, the check below finds anything a login could change.

A stop rolls back the transaction it happens in. In operator mode that is the only transaction, so nothing
changes. In read-only mode the first transaction has already taken LOGIN away, and the logins stay without it
until a run passes. The stop messages say which of the two happened.

The DBA then reads the evidence (the catalog as it is, and the pgaudit `role` lines that show who made the
change) before anything is repaired by hand. A login that is beyond repair is retired: take it out of
`operators`, and give the person a new login name.

## Read-only mode

`read_only = true` is for people who must only read the service database, such as the person running a
pre-cutover check (the loan service's old-schedule check). It changes three things:

- Each login's sessions default to `default_transaction_read_only = on`.
- `login_sql` is two transactions. The first checks the group's mark and stops, touching no role, when the group
  exists without the read-only mark (for example when it is an operator instance's group). Otherwise it takes
  LOGIN away from every login that carries this group's mark and commits. The second makes the desired state,
  leaves the logins without LOGIN, and then checks what each listed login can do in `database_name`, outside the
  system schemas. It gives LOGIN back only when the check passes. When the check or anything else stops the
  second transaction, the logins stay without LOGIN until a run passes.
- The check is what PostgreSQL decides for each login (`has_*_privilege` on the login, so its own grants and
  those of the group, `rds_iam` and PUBLIC all count). It stops, naming each finding and who holds it, on:
  CREATE on the database or a schema; INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES or TRIGGER on a table or view
  of any kind, or a column-level INSERT, UPDATE or REFERENCES; USAGE or UPDATE on a sequence; EXECUTE on a
  SECURITY DEFINER function; a default privilege that would give the group, a login, `rds_iam` or PUBLIC a write
  privilege on future tables or sequences, or CREATE on future schemas; a large object a login may write; and
  anything the group owns.
  - A login may write a large object that is owned by, or has UPDATE granted to, a role the login has the
    privileges of (itself, the group, `rds_iam`, or a role one of them inherits) or PUBLIC. That covers a large
    object a service user in `rds_iam` made as `rds_iam`. When `lo_compat_privileges` is on, PostgreSQL checks no
    large-object privilege, so the check stops on that too.
  - A SECURITY DEFINER function that returns `event_trigger` is exempt: only an event trigger runs it, and only a
    superuser can create one. pgaudit's two functions are such; the `aurora-postgresql` bootstrap creates them in
    `public` when the master runs `CREATE EXTENSION pgaudit`, and PUBLIC may execute them. A trigger function is
    not exempt, because a login that may create a temporary table could attach it to that table.
  - Any other SECURITY DEFINER function that belongs to an extension is exempt only when the extension's owner
    is not a service user and owns no schema of the database, so a function a service role added to its own
    extension is reported.

The service's migration still grants the group (SELECT on what the check reads). Re-run `login_sql` after every
release of the service: a release whose migration gave the group more than reading makes it stop, the logins
stay off, and the DBA takes that to the service's squad before anyone uses these logins again.

A run that stops does not end sessions that are already open. Such a session keeps every right the logins now
have, so after a release that gave the group a write privilege it can still write. After a failed run, the DBA
ends those sessions as the master user, naming every login of the instance (this needs `pg_signal_backend`,
which RDS gives `rds_superuser`):

```sql
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename IN ('op_<name>_ro', 'op_<other>_ro');
```

The message of a failed check says so too.

Each module instance needs its own `operator_group_role`, and the group's mark names the mode. A read-only
instance given an operator instance's group stops in its first transaction and touches no role, and the other
way round the operator instance stops too. A login belongs to one group, so a person who needs both kinds of
access gets one login per module instance (for example `op_<name>` in the operator instance and `op_<name>_ro`
in the read-only one); the SQL stops when a listed login carries another group's mark.

## Order

1. Apply the stack that calls this module (creates the policy).
2. The account-baseline owner adds `policy_name` to the operators' permission set.
3. The DBA runs `login_sql` as the master user in `database_name`, always as the same master user (the one that
   created the roles):
   `terraform output -raw <module>_login_sql > login.sql`, then
   `psql "<master connection>" -v ON_ERROR_STOP=1 -f login.sql`.
   Do not add `--single-transaction`: the file carries its own `BEGIN` and `COMMIT` (one transaction in operator
   mode, two in read-only mode). The first time, in dev, check that an operator can sign in with IAM: the
   logins are in `rds_iam` without SET, which PostgreSQL accepts but which has not been tried on Aurora yet.
4. Deploy the service release whose migration grants the group (it fails closed while the group is missing).
5. In read-only mode, run `login_sql` again: it now checks the grants that release made.

To remove a person: delete their entry and apply, which takes away their connect permission; then run the new
`login_sql`, which retires their login. Retiring does not end a session that is already open.

When a run stops in operator mode, its one transaction rolls back and nothing changes: logins keep the state they
had, a person taken out of `operators` is not retired yet, and a login that was changed by hand keeps working
until the DBA deals with it.

## Connecting

Only from the person's own workstation, through a port-forwarding session to the operator host
(`operator-access`). Needed: the AWS CLI with the Session Manager plugin, psql, the RDS CA bundle, and a profile
for the person's own Identity Center permission set. That permission set must allow `ssm:StartSession` on the
operator host with the document `AWS-StartPortForwardingSessionToRemoteHost`, and `kms:GenerateDataKey` on the
host's session key (see the `operator-access` README). The service database's security group must admit the
operator host (`operator-access` output `operator_security_group_id`). The host needs nothing else for this path:
its egress already allows 5432 inside the VPC.

```bash
aws sso login --profile <your profile>

# Terminal 1: the tunnel, open while you work.
aws ssm start-session --profile <your profile> --target <operator host instance id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=<writer endpoint>,portNumber=5432,localPortNumber=15432

# Terminal 2: a token for this one psql process, then the connection through the tunnel.
DB_TOKEN="$(aws rds generate-db-auth-token --profile <your profile> --hostname <writer endpoint> --port 5432 --region <region> --username op_<name>)"
export PGPASSWORD="${DB_TOKEN}"
psql "host=<writer endpoint> hostaddr=127.0.0.1 port=15432 dbname=<database_name> user=op_<name> sslmode=verify-full sslrootcert=<rds-ca bundle>"
unset PGPASSWORD DB_TOKEN
```

Both `aws` commands name your profile, so each terminal signs with your own permission set and never with a
default profile the workstation may also have.

The token is made for the writer endpoint on port 5432, because that is what the database checks. `host=` keeps
the certificate check on the endpoint name, and `hostaddr=127.0.0.1 port=15432` sends the traffic into the
tunnel. The token is valid for 15 minutes, and anyone who has it can connect as you within that time. Hand it to
psql through `PGPASSWORD` as above, so it is not printed. Do not paste it at psql's password prompt: psql 13 and
older cut a typed password at 100 bytes, and a token is about 1 KB.

Never make a token, and never paste or export AWS credentials, in a shell session on the operator host. Shell
sessions there all run as the same operating-system user, and their full transcript goes to the session log
group in CloudWatch. A port-forwarding session has no transcript; its record is the CloudTrail `StartSession`
event and the database's own log.

## Residual risk

- `rds-db:connect` is authorised when the connection is made and is not recorded in CloudTrail. The record is
  the database's own log, exported to CloudWatch: the connection and disconnection lines, and the pgaudit lines
  of the login's statements (`pgaudit.log` on each login, see above). `aurora-postgresql` sets
  `log_connections = 1` and `log_disconnections = 1`; a service that keeps its own parameter group (loan, ledger)
  must set them too. `login_sql` refuses to run without pgaudit.
- The policy binds a login to a user name, but it only adds an allow. Others can still connect as
  `op_<person>`, and the audit lines then name that person:
  - any principal with a broader `rds-db:connect` (for example `AdministratorAccess`, `PowerUserAccess` or
    `rds-db:*` on `*`) can make a token for any login, because every login is in `rds_iam`;
  - whoever administers the identity source can rename an account's `userName` to another person's, and that
    account then matches the other person's statement;
  - a role whose callers choose their own session name must never get this policy.

  Recommended outside this module: a service control policy or permission boundary that denies `rds-db:connect`
  on `arn:*:rds-db:*:*:dbuser:*/op_*` unless `aws:PrincipalArn` is like the operators' role
  `arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_<permission set>_*`, and identity-source
  change alerts on `userName`.
- The master user created every login, so PostgreSQL 16 gives it ADMIN on each of them. It can set a password on
  a login, grant itself the login, or take `rds_iam` away, and then connect or act as that person. `login_sql`
  stops on a login that has a member or lost `rds_iam`. It cannot read the stored value: for the master `pg_roles` shows
  `********` and `pg_authid` needs a superuser. So every run sets `PASSWORD NULL`, which also removes a password
  without a trace in the catalog. Recommended: an alarm on `ALTER ROLE op_*`, and on `GRANT` or `REVOKE` that
  names an `op_` login, by the master outside a `login_sql` run (the cluster's pgaudit `role` class logs them).
  Anyone with the master user (or the schema owner) can also act in the database under that shared name; their
  use is for the DBA process, not for operator tasks.
- The three role-wide settings are session defaults. A login can change `idle_in_transaction_session_timeout` and
  `default_transaction_read_only` with `SET` in its own session, or for all its sessions with
  `ALTER ROLE CURRENT_USER SET`. The next run sets the role-wide values again, and the pgaudit `role` lines show
  the login's `ALTER ROLE`. A login cannot change `pgaudit.log`, which only a superuser or `rds_superuser` may set.
  The idle timeout stops a transaction forgotten at the prompt, not one an operator keeps open on purpose; the
  database's log shows such a session, and `pg_terminate_backend` by the DBA ends it.
- In read-only mode the privileges are what keep the logins from writing, and `login_sql` proves them only when
  it runs, so it is re-run after every release. A grant made by hand between runs is not seen until the next run.
  The check covers `database_name` only. A login can connect to any database of the cluster that it may
  `CONNECT` to, because `rds-db:connect` names no database. In another database, anything a login comes to own,
  or a privilege granted to the login itself, makes the next run stop. Privileges held there by the group,
  `rds_iam` or PUBLIC are not checked.
- Any role can create large objects (`lo_create` and `lo_from_bytea` are granted to PUBLIC, and the master
  cannot revoke that on Aurora). In read-only mode the read-only default is what stops a login from doing so, and
  a login can turn that default off. A large object a login creates belongs to the login, so the next run stops.
  A login cannot make one that the group or `rds_iam` owns, because it cannot `SET ROLE` to either. One that
  someone else made as `rds_iam` (a service user in `rds_iam`, say) is reported by the read-only check, but does
  not stop an operator-mode run.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | `dev`, `staging` or `prod`. |
| `service_slug` | `string` | required | Service slug; part of the policy name and of the group's mark. |
| `database_name` | `string` | required | The service database; the SQL refuses any other. |
| `cluster_resource_id` | `string` | required | Aurora `cluster_resource_id` (`cluster-<ID>`), not the cluster identifier. |
| `operator_group_role` | `string` | required | NOLOGIN group of the logins; not `pg_*`, `rds_*`, `op_*`, `postgres` or `rdsadmin`. |
| `operators` | `map(string)` | required | Identity Center user name => login `op_<lowercase name>`; 1 to 20, one login per person. User names are 2 to 64 characters of `A-Z a-z 0-9 + = , . @ _ -`, so no `*`, `?`, `$`, `{` or `}`, which IAM reads as wildcards or policy variables. The plan fails when the policy would exceed 6,144 characters (twenty user names and logins of about 30 and 20 characters fit). |
| `reserved_db_users` | `list(string)` | required | The service's master, runtime and migration users. None may be the group or a login; the SQL stops when one is a member of the group and leaves the membership for the DBA to look at. |
| `connection_limit` | `number` | `2` | Sessions per login, 1..10. |
| `idle_in_transaction_timeout_seconds` | `number` | `60` | `idle_in_transaction_session_timeout` of each login, 5..600 s. |
| `read_only` | `bool` | `false` | Read-only logins (see Read-only mode); the policy is named `-db-readonly-login`. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|---|---|
| `policy_arn` | The connect policy. |
| `policy_name` | Name for the permission set's customer managed policy reference. |
| `operator_logins` | User name => login. |
| `operator_group_role` | The group the service's migration grants. |
| `login_sql` | Desired-state SQL for the DBA (holds no secret). |
