# DevOps Assessment — Terraform + Database Reliability

Terraform for an `Internet → ALB → ECS/Fargate → RDS` stack on AWS, plus a local
PostgreSQL setup for the backup, restore and query-optimisation tasks.

Nothing here is deployed to AWS. The Terraform is written to be deployable —
`fmt`, `init`, `validate` and `plan` all pass — and the database half runs
entirely on Docker Compose.

---

## Quick start

```bash
# database
docker compose up -d --wait        # schema + indexes + 20k seeded bookings
./scripts/explain.sh               # query plans, with and without the index
./scripts/backup.sh                # timestamped dump into ./backups
./scripts/restore.sh               # restore into a fresh db and verify it

# terraform
./scripts/tf-local-backend.sh dev  # use local state (no AWS account needed)
cd infra/envs/dev
terraform init && terraform validate && terraform plan -refresh=false
```

Requirements: Docker (with the Compose plugin) and Terraform >= 1.9. No local
`psql` or `pg_dump` needed — every script runs the client inside the container.

---

## Where each part of the brief lives

| Part | Deliverable | Files |
| --- | --- | --- |
| 1 | VPC, subnets, 3 security groups, ECS/Fargate, RDS | [`infra/modules/`](infra/modules) |
| 2 | dev + prod environments | [`infra/envs/dev`](infra/envs/dev), [`infra/envs/prod`](infra/envs/prod) |
| 3 | fmt / init / validate / plan on PRs | [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) |
| 4 | Local database | [`docker-compose.yml`](docker-compose.yml), [`db/migrations/`](db/migrations) |
| 5 | Seed data + index | [`db/seed/0003_seed.sql`](db/seed/0003_seed.sql), [`db/migrations/0002_indexes.sql`](db/migrations/0002_indexes.sql), and [below](#part-5--the-index-and-why) |
| 6 | Backup and restore | [`scripts/backup.sh`](scripts/backup.sh), [`scripts/restore.sh`](scripts/restore.sh) |

```
.
├── infra/
│   ├── modules/
│   │   ├── network/      VPC, subnets, NAT, endpoints, flow logs, security groups
│   │   ├── ecs/          cluster, ALB, task definition, service, autoscaling, IAM
│   │   └── rds/          subnet group, parameter group, PostgreSQL instance
│   └── envs/
│       ├── dev/          small, cheap, disposable
│       └── prod/         multi-AZ, protected, retained
├── db/
│   ├── migrations/       0001 schema, 0002 indexes
│   ├── seed/             0003 seed data
│   └── queries/          the reporting query + before/after EXPLAIN
├── scripts/              backup, restore, seed, psql, explain, tf helper
└── .github/workflows/    terraform plan on PRs; database round-trip test
```

---

# Part 1 — Infrastructure

```
                    internet
                       |
                  :80  |   security group: <name>-alb
              +--------v---------+
              |       ALB        |   public subnets, one per AZ
              +--------+---------+
                       |   :80, source = ALB security group
              +--------v---------+
              |  ECS / Fargate   |   private subnets, no public IP
              |  (awsvpc ENI)    |   security group: <name>-service
              +--------+---------+
                       |   :5432, source = service security group
              +--------v---------+
              | RDS PostgreSQL   |   private subnets, publicly_accessible = false
              +------------------+
```

**RDS is private and reachable only from the service.** Three things enforce
that, and any one of them alone would not be enough:

1. The DB subnet group contains private subnets only.
2. `publicly_accessible = false`.
3. The database security group has exactly one ingress rule, and its source is
   the *service security group* — not a CIDR. No bastion rule, no office range,
   no `0.0.0.0/0` on 5432.

Tasks run with `assign_public_ip = false` and reach the internet through NAT.

### Why the security groups live in the network module

They form a chain — the ALB group references the service group, which references
the database group. Splitting them across the `ecs` and `rds` modules creates a
dependency cycle: `ecs` would need the database group to write its egress rule
while `rds` would need the service group to write its ingress rule.

Putting all three in `network` breaks the cycle, keeps the environment wiring a
straight line (`network -> rds -> ecs`), and has the useful side effect that the
entire traffic policy is readable in
[one file](infra/modules/network/security_groups.tf).

Egress is enumerated rather than left open. Worth knowing: on Fargate, image
pulls and log shipping go out over the *task* ENI, so the service group needs
443 and DNS even though nginx itself never makes an outbound call.

### Credentials

`manage_master_user_password = true` — RDS generates the password, stores it in
Secrets Manager and rotates it. Terraform only ever handles the secret ARN.

The common alternative (`random_password` + `aws_secretsmanager_secret_version`)
writes the plaintext password into the state file permanently, which is the most
likely way a credential escapes an otherwise careful setup. The ECS task
definition references the secret by ARN, so the password is resolved by the ECS
agent at start-up and never appears in the task definition or in
`terraform show`.

The execution role and the task role are separate. Merging them — the usual
shortcut — hands the application permission to read every secret the task
definition references.

---

# Part 2 — Environments

`infra/envs/dev` and `infra/envs/prod` call the same three modules with
different numbers. There is no `count = var.environment == "prod" ? 1 : 0`
anywhere in the modules: every difference is a variable, set in that
environment's `terraform.tfvars`. Conditionals keyed on environment name are how
two environments quietly stop resembling each other until prod is the only one
anyone trusts.

|  | dev | prod |
| --- | --- | --- |
| VPC CIDR | `10.10.0.0/16` | `10.20.0.0/16` (non-overlapping) |
| Availability zones | 2 | 3 |
| NAT gateways | 1, shared | 1 per AZ |
| Interface VPC endpoints | off | ECR, Logs, Secrets Manager, SSM |
| Flow logs | off | on |
| Fargate task | 0.25 vCPU / 512 MiB | 1 vCPU / 2 GiB |
| Task count | 1 (scales 1–2) | 3 (scales 3–12) |
| Log retention | 7 days | 90 days |
| ECS Exec | on | off |
| ALB deletion protection | off | on |
| RDS instance | `db.t4g.micro`, single-AZ | `db.r7g.large`, Multi-AZ |
| RDS storage | 20 -> 50 GiB | 100 -> 1000 GiB |
| **Backup retention** | **1 day** | **30 days** |
| **Deletion protection** | **false** | **true** |
| Final snapshot on destroy | skipped | taken |
| Performance Insights | off | on |
| Enhanced monitoring | off | 30s |
| Database changes | applied immediately | maintenance window |
| State bucket | `bookings-tfstate-dev-ap-south-1` | `bookings-tfstate-prod-ap-south-1` |

A few of the choices behind that table:

- **One NAT gateway in dev** saves roughly a NAT gateway's monthly cost and makes
  one AZ a hard dependency for all egress. Fine when the environment going down
  for an hour costs nothing; not fine in prod.
- **Interface endpoints in prod only.** They cost a flat hourly rate per AZ and
  save per-GB NAT charges, so it is a crossover — worth it under real traffic,
  not worth it in an account that idles. The S3 *gateway* endpoint is free and is
  created in both, because ECR stores image layers in S3 and without it every
  task start pulls those layers out through the NAT gateway.
- **Separate state buckets, not just separate keys.** A mistyped
  `-backend-config` or a stale `AWS_PROFILE` should fail with "access denied",
  not reach the wrong environment's state.
- `use_lockfile = true` uses S3 conditional writes for state locking, which
  replaces the old DynamoDB lock table (Terraform 1.10+).

### Reviewing the Terraform without an AWS account

Both environments declare an S3 backend, so a plain `terraform init` tries to
reach a bucket you cannot see. Rather than commenting the backend out — and
shipping a repo that does not show how state is configured — there is a helper:

```bash
./scripts/tf-local-backend.sh dev      # writes a gitignored local_override.tf
cd infra/envs/dev
terraform init
terraform validate
terraform plan -refresh=false          # needs AWS credentials, see below
./scripts/tf-local-backend.sh dev --remove
```

It works by dropping a Terraform *override file* beside the backend config;
override files replace the matching block at load time, so the committed
configuration is never edited. The file is gitignored and cannot be committed by
accident.

`terraform plan` still needs credentials — the provider calls
`DescribeAvailabilityZones` before it can lay out subnets. Any account works, and
the plan creates nothing. Against an empty region, dev plans **48 resources to
add** and prod **70**, with no warnings.

---

# Part 3 — GitHub Actions

Two workflows, both on pull requests.

**[`terraform.yml`](.github/workflows/terraform.yml)** — `fmt -check -recursive`
in its own job, then a matrix of `init` / `validate` / `plan` over dev and prod
(`fail-fast: false`, so a broken dev does not hide the state of prod). The plan
is published three ways: as a PR comment, as a workflow artifact (`tfplan` and
`plan.txt`), and in the job log.

The comment is keyed on a hidden marker and *updated* rather than appended, so a
long-running PR ends up with one current plan per environment instead of twenty
stale ones. Output over 60,000 characters is truncated with a pointer to the
artifact, because GitHub rejects comments above 65,536.

**[`database.yml`](.github/workflows/database.yml)** — runs `shellcheck`, brings
the compose stack up, prints the query plans, takes a backup, **deletes every
Delhi booking**, then restores and asserts the restored data matches the backup.
It is the same sequence a reviewer runs by hand; having CI run it means the
scripts are tested rather than merely written.

### Enabling the plan step

`plan` is gated on a repository variable, so the workflow stays green in a repo
with no AWS account attached — it runs fmt, init and validate against the real
configuration and comments that the plan was skipped, instead of failing on
credentials it was never given.

To turn it on, set two repository **variables** (Settings -> Secrets and
variables -> Actions -> Variables):

| Variable | Example |
| --- | --- |
| `AWS_ROLE_ARN` | `arn:aws:iam::111122223333:role/github-actions-terraform-plan` |
| `AWS_REGION` | `ap-south-1` |

No secrets. The workflow requests an OIDC token (`id-token: write`) and assumes
that role, so there are no long-lived access keys in the repository. The role's
trust policy:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike": { "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:pull_request" }
  }
}
```

Scope the `sub` condition to the repository — a trust policy that only checks the
audience can be assumed from *any* GitHub repository. For plan-only CI the role
needs read access plus write on the state bucket; `ReadOnlyAccess` plus an inline
S3 policy is the usual starting point.

---

# Part 4 — Local database

```bash
docker compose up -d --wait
```

PostgreSQL 16, matching `db_engine_version` in the Terraform so local and RDS do
not drift apart. Published on **port 55432**, not 5432, because a lot of laptops
already have a Postgres or pgAdmin holding that port. Override it in `.env` —
copy `.env.example`.

On first boot, `/docker-entrypoint-initdb.d` runs three files in order:

| File | What it does |
| --- | --- |
| `db/migrations/0001_schema.sql` | `hotel_bookings`, `booking_events` |
| `db/migrations/0002_indexes.sql` | the reporting index and the FK index |
| `db/seed/0003_seed.sql` | 20,000 bookings and roughly 16,000 events |
| `db/migrations/0004_pg_stat_statements.sql` | the `pg_stat_statements` extension |

Those files only run when the data directory is empty. To start over:
`docker compose down -v && docker compose up -d --wait`. To reset the data
without a full re-init: `./scripts/seed.sh` — all three files are re-runnable.

The healthcheck runs `pg_isready -h 127.0.0.1` rather than over the unix socket.
That detail matters: while the entrypoint is running the migration and seed files
it starts a *temporary* server bound to the socket only. A socket-based check
reports "ready" mid-seed, and everything downstream races it.

`shared_preload_libraries=pg_stat_statements` is set on the container command
line, because that setting can only be changed at server start. The RDS
parameter group sets the same value, so a query investigated locally behaves the
way it will in RDS. To see what is actually costing time:

```bash
./scripts/psql.sh -f /db/queries/slow_queries.sql
```

### Schema notes

The tables match the brief, including `TIMESTAMP` rather than `TIMESTAMPTZ`. In a
real booking system I would use `TIMESTAMPTZ` — `NOW() - INTERVAL '30 days'`
against a timezone-naive column silently means "30 days in whatever the server's
timezone happens to be", which shows up later as an off-by-a-few-hours
discrepancy in a daily report that nobody can reproduce.

Two additions: a foreign key from `booking_events.booking_id` to
`hotel_bookings.id` with `ON DELETE CASCADE`, and check constraints for
`checkout_date > checkin_date` and `amount >= 0`.

---

# Part 5 — the index, and why

The query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

The index:

```sql
CREATE INDEX hotel_bookings_city_created_at_idx
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

**Why 20,000 rows and not 100.** The brief asks for at least 100 bookings. At 100
rows the whole table is one or two pages and a sequential scan is genuinely the
cheapest plan — Postgres would ignore this index and the exercise would prove
nothing. The seed generates 20,000 bookings spread over 180 days across 13
cities, which puts `city = 'delhi' AND created_at >= now() - 30 days` at roughly
2% selectivity: squarely in the range where an index wins.

**Why `(city, created_at)` in that order.** `city` is an equality predicate and
`created_at` is a range. A B-tree can use only one range column, and only after
every equality column to its left. With `(city, created_at)` the scan is one
contiguous stretch of the tree. Reversed — `(created_at, city)` — the scan would
walk 30 days of *every* city and throw away twelve-thirteenths of what it read.

**Why `INCLUDE (org_id, status, amount)`.** The query needs three more columns:
two to group by and one to sum. Carrying them in the index leaf pages lets
Postgres answer entirely from the index — an **index-only scan**, with no heap
access at all.

`INCLUDE` rather than adding them as key columns, because included columns are
stored only in the leaves and not in the internal nodes. The tree stays
shallower, and they cannot be used for ordering or filtering — which is honest,
because here they never are.

**The catch with index-only scans:** they only skip the heap for pages marked
all-visible in the visibility map. Straight after a bulk load nothing is marked,
so the plan reports a large `Heap Fetches` and performs like a plain index scan.
The seed ends with `VACUUM (ANALYZE)` for exactly this reason, and it is why the
production version of this change is `CREATE INDEX CONCURRENTLY` followed by
`VACUUM ANALYZE`, not just `CREATE INDEX`.

### Seeing it

```bash
./scripts/explain.sh
```

[`db/queries/analytics.sql`](db/queries/analytics.sql) drops the index *inside a
transaction*, runs `EXPLAIN (ANALYZE, BUFFERS)`, and rolls back — so you get the
un-indexed plan for comparison without losing the index or re-seeding. The plan
shape changes like this:

```
before   Seq Scan on hotel_bookings
           Filter: city = 'delhi' AND created_at >= ...
           Rows Removed by Filter: ~19,600
           -> HashAggregate

after    Index Only Scan using hotel_bookings_city_created_at_idx
           Index Cond: city = 'delhi' AND created_at >= ...
           Heap Fetches: 0
           -> HashAggregate
```

`Rows Removed by Filter` on the "before" plan is the thing to look at: it is the
work the index removes. `shared read` in the `BUFFERS` output drops by roughly
the same proportion.

### Things I deliberately did not index

- **A partial index** (`... WHERE created_at >= now() - interval '30 days'`)
  looks tempting and does not work: index predicates must be immutable and
  `now()` is not. Even if it were allowed, the predicate would freeze at build
  time and the index would silently stop matching the query as days passed.
- **A GIN index on `payload`.** No query here searches inside the JSONB. GIN
  indexes are large and slow to update; adding one speculatively costs write
  throughput for nothing.
- **An index on `status` or `org_id` alone.** Both are low-cardinality and
  neither is a filter — they are only grouped on, and the grouping is already fed
  by the index above.

The one other index in the migration is `booking_events (booking_id, created_at)`.
Postgres does not index a foreign key automatically, so without it deleting a
booking sequentially scans `booking_events`, and "give me this booking's history"
does the same.

---

# Part 6 — Backup and restore

```bash
./scripts/backup.sh                        # ./backups/bookings-20260918T101500Z.dump
./scripts/restore.sh                       # newest dump -> a fresh database, verified
./scripts/restore.sh --into bookings_check
./scripts/restore.sh --replace             # overwrite the live local database
```

`backup.sh` writes `pg_dump --format=custom` — compressed, and restorable
selectively, which a plain SQL dump is not. The dump goes to a `.partial` file
and is renamed only after `pg_dump` exits cleanly, so an interrupted run never
leaves behind something that looks like a usable backup. Old dumps are pruned to
`BACKUP_RETENTION` (default 7).

Alongside each dump it writes a `.meta` sidecar:

```
database=bookings
created_at_utc=2026-09-18T10:15:00Z
server_version=16.4
hotel_bookings_rows=20000
booking_events_rows=16043
sum_amount=502184311.55
booking_id_md5=6f1e...
sha256=9b0c...
```

### How to verify the restore worked

`restore.sh` does it for you. It restores into a **new** database — nothing
existing is touched — then recomputes that fingerprint and compares it against
the sidecar, exiting non-zero on any mismatch:

```
==> verifying 'bookings_restore_20260918101632' against the fingerprint taken at backup time
  check                  restored value                         result
  hotel_bookings rows    20000                                  PASS
  booking_events rows    16043                                  PASS
  sum(amount)            502184311.55                           PASS
  booking id md5         6f1e...                                PASS
  ok all checks passed
```

Row counts alone would pass even if every row held the wrong data, so the
fingerprint also covers `sum(amount)` and an MD5 over every booking id in sorted
order. Comparing against the sidecar rather than against the live database
matters: it is what makes the check meaningful *after* data has been lost, which
is the only time anyone runs a restore.

To prove it end to end — destroy data, then get it back:

```bash
./scripts/backup.sh
./scripts/psql.sh -c "DELETE FROM hotel_bookings WHERE city = 'delhi'"
./scripts/psql.sh -c "SELECT count(*) FROM hotel_bookings"    # ~4,600 rows gone
./scripts/restore.sh --replace                                 # type 'bookings' to confirm
./scripts/psql.sh -c "SELECT count(*) FROM hotel_bookings"    # back to 20000
```

The restore runs with `--single-transaction`, so an error leaves the target
database empty rather than half-populated, and with `--no-owner --no-privileges`,
so the dump restores cleanly under a different role than it was taken with.

`--replace` asks you to type the database name before dropping anything; `--yes`
skips the prompt, for CI.

---

## Verification checklist

```bash
# Terraform
terraform fmt -check -recursive infra
./scripts/tf-local-backend.sh dev && cd infra/envs/dev
terraform init && terraform validate && terraform plan -refresh=false
cd ../../.. && ./scripts/tf-local-backend.sh dev --remove

# Database
docker compose up -d --wait
./scripts/explain.sh
./scripts/backup.sh
./scripts/restore.sh
docker compose down -v
```

## Trade-offs, and what I would add next

Left out on purpose, and what it would take to add:

- **HTTPS.** The ALB has an HTTP listener only. A production version adds an ACM
  certificate, an HTTPS listener, and turns port 80 into a permanent redirect —
  that needs a real domain and a validated certificate, so it cannot be part of a
  plan-only stack. The security group already takes an `alb_ingress_ports` list.
- **ALB access logs.** They need an S3 bucket with a region-specific bucket
  policy — worth having, but a second stack's worth of resources.
- **WAF** in front of the ALB.
- **Alarms.** 5xx rate, target response time, ECS task count pinned at the
  ceiling, RDS free storage and CPU credit balance. The stack emits the metrics;
  nothing consumes them yet.
- **A real application image.** The task runs nginx as a placeholder. It already
  receives `DB_HOST`, `DB_PORT` and `DB_NAME` as environment variables and
  `DB_CREDENTIALS` from Secrets Manager, so a real backend would only need to
  read them.
- **Migrations in the deploy path.** The SQL files here are applied by Compose on
  first boot. Against RDS they belong in a one-off ECS task or a migration tool
  (Flyway, Alembic) that runs before the service rolls, not on container start.
