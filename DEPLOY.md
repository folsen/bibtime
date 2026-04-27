# Deploying BibTime to Fly.io

BibTime runs on a single Fly machine per environment, backed by a persistent
volume for SQLite and continuous object-storage replication via
[Litestream](https://litestream.io/). Two environments are configured:

| Environment | Config file        | Default app name   |
| ----------- | ------------------ | ------------------ |
| Production  | `fly.toml`         | `bibtime`          |
| Staging     | `fly.staging.toml` | `bibtime-staging`  |

The committed toml files contain no customer-specific values. Domains,
API keys, and bucket names are injected per-app via `fly secrets set`.

If you'd rather self-host, see [Self-hosting alternatives](#self-hosting-alternatives)
below for Docker and bare-metal/systemd paths. The
[Environment variables](#environment-variables) reference at the bottom
applies to all deployment targets.

## First-time setup

### 1. Install the Fly CLI and sign in

```sh
brew install flyctl
fly auth signup   # or: fly auth login
```

### 2. Create both apps

The committed app names (`bibtime`, `bibtime-staging`) will be taken on
Fly's shared namespace. For a fork, pick your own names and pass
`--app your-name` to every subsequent command, or edit the toml files.

```sh
fly apps create bibtime
fly apps create bibtime-staging
```

### 3. Create a persistent volume for each app

SQLite lives on `/data`. One volume per app, in the same region as the app.

```sh
fly volumes create bibtime_data          -a bibtime          -r arn -s 3
fly volumes create bibtime_staging_data  -a bibtime-staging  -r arn -s 3
```

### 4. Provision object storage for Litestream

Use Fly's native [Tigris](https://fly.io/docs/reference/tigris/) — one
command, billed on the same invoice, S3-compatible. Run once per app so
each environment has its own bucket:

```sh
fly storage create -a bibtime          # exports creds as secrets on the app
fly storage create -a bibtime-staging
```

`fly storage create` prints bucket credentials to stdout and sets them
as `AWS_*` secrets on the app. Copy those values (endpoint URL, bucket
name, region, access key ID, secret access key) and register them under
the `LITESTREAM_*` names our `litestream.yml` expects:

```sh
fly secrets set -a bibtime \
  LITESTREAM_ENDPOINT=https://fly.storage.tigris.dev \
  LITESTREAM_BUCKET=<bucket-name-from-output> \
  LITESTREAM_REGION=auto \
  LITESTREAM_ACCESS_KEY_ID=<from output> \
  LITESTREAM_SECRET_ACCESS_KEY=<from output>
# Repeat with `-a bibtime-staging` using the staging bucket's credentials.
```

(Or set them by hand from another S3-compatible provider — Cloudflare R2,
AWS S3, Backblaze B2 all work the same.)

### 5. Set the remaining secrets per app

```sh
# Common
fly secrets set -a bibtime \
  PHX_HOST=bibtime.yourdomain.com \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  MAILER_FROM_ADDRESS=no-reply@yourdomain.com \
  RESEND_API_KEY=re_xxx

fly secrets set -a bibtime-staging \
  PHX_HOST=staging.yourdomain.com \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  MAILER_FROM_ADDRESS=no-reply@yourdomain.com \
  DEV_TOOLS_BASIC_AUTH_USERNAME=admin \
  DEV_TOOLS_BASIC_AUTH_PASSWORD=$(openssl rand -base64 24)
# Staging omits RESEND_API_KEY so mail is captured by Swoosh.Adapters.Local
# and viewable at /dev/mailbox (staging is built with MIX_ENV=staging, which
# enables the mailbox preview route — see config/staging.exs).
# DEV_TOOLS_BASIC_AUTH_* guards /dev/mailbox, /dev/dashboard, /dev/emails —
# staging fails to boot without them.
```

Optional, if you use them:

```sh
fly secrets set -a bibtime \
  STRIPE_SECRET_KEY=sk_live_xxx \
  STRIPE_WEBHOOK_SECRET=whsec_xxx \
  PHOTO_STORAGE=s3 \
  S3_BUCKET=... \
  AWS_ACCESS_KEY_ID=... \
  AWS_SECRET_ACCESS_KEY=... \
  AWS_REGION=...
```

If you're using Stripe, create a webhook endpoint in the Stripe Dashboard
(Developers → Webhooks → Add endpoint) pointing at
`https://<PHX_HOST>/webhooks/stripe` and subscribe to these events:

- `checkout.session.completed` — marks a registration paid and finalizes the participant
- `charge.refunded` — records refunds against the matching payment

The endpoint's signing secret is what you set as `STRIPE_WEBHOOK_SECRET` above.
Register separate endpoints for prod and staging so each environment gets its
own signing secret.

### 6. First deploy

```sh
fly deploy                        # prod
fly deploy -c fly.staging.toml    # staging
```

### 7. Point DNS at Fly

```sh
fly ips list -a bibtime           # shows the v4/v6 addresses
fly certs add bibtime.yourdomain.com -a bibtime
```

Create records at your DNS provider (Netlify DNS, Route 53, Cloudflare —
all work the same):

- `A` → the v4 address shown by `fly ips list`
- `AAAA` → the v6 address
- Or a single `CNAME` → `bibtime.fly.dev` (apex domains can't CNAME; use A/AAAA)

`fly certs show` reports when the Let's Encrypt cert is issued.

## Log aggregation (Better Stack)

Production logs are shipped to [Better Stack
Telemetry](https://betterstack.com/telemetry) via the official
[fly-log-shipper](https://github.com/superfly/fly-log-shipper). This
captures both Phoenix log output and Fly platform events (machine
restarts, OOM kills, deploy failures) in a single searchable stream that
AI agents can query through `scripts/logs.sh`.

### One-time setup

1. **Create a source in Better Stack.** Telemetry → Sources → Connect
   source → "Fly.io". Pick a name per environment, e.g.
   `bibtime-prod` and `bibtime-staging`. Copy the **source token** and
   the **ingesting host** (e.g. `s12345.eu-nbg-2.betterstackdata.com`)
   from the source's setup page.

2. **Create the shipper app on Fly** (no `fly launch` — we ship a
   committed config at `fly.logshipper.toml`, so the app just needs to
   exist on Fly's side first):

   ```sh
   fly apps create bibtime-log-shipper
   ```

3. **Set secrets on the shipper app:**

   ```sh
   ORG=personal   # your Fly org slug — `fly orgs list`
   fly secrets set -a bibtime-log-shipper \
     ORG=$ORG \
     ACCESS_TOKEN=$(fly tokens create readonly $ORG | cut -d' ' -f2) \
     BETTER_STACK_SOURCE_TOKEN=<source token> \
     BETTER_STACK_INGESTING_HOST=<ingesting host without https://>

   fly deploy -c fly.logshipper.toml
   ```

   The shipper consumes Fly's NATS log feed for the entire org, so one
   shipper covers prod and staging. Create a second shipper (and a
   second Better Stack source) only if you want logs split per env.

   **Why a separate config file:** the shipper's `app =` differs from
   the Phoenix app, and it runs a pre-built image with no `[build]`
   context from this repo. Keeping it in `fly.logshipper.toml` lets the
   config live alongside `fly.toml` / `fly.staging.toml` without the
   risk of `fly launch` clobbering the production config.

4. **Verify** logs land in Better Stack — open the source's Live Tail.
   You should see `bibtime`'s Phoenix output within a few seconds.

### Querying logs from the dev machine

`scripts/logs.sh` runs ClickHouse SQL queries against Better Stack's
read API (designed so AI assistants can debug prod incidents). Set up
read credentials once:

1. In Better Stack → Sources → click the `bibtime-prod` source → Connect
   → "Connect remotely" / "SQL API". Copy the host, username, password,
   and the source's table name (`tNNNNNN_bibtime_prod_logs`).

2. Add to `.env` (gitignored):

   ```sh
   BETTERSTACK_QUERY_HOST=eu-nbg-2-connect.betterstackdata.com
   BETTERSTACK_QUERY_USERNAME=<from Better Stack>
   BETTERSTACK_QUERY_PASSWORD=<from Better Stack>
   BETTERSTACK_QUERY_TABLE=t123456_bibtime_prod_logs
   ```

3. Test it:

   ```sh
   scripts/logs.sh tail 20 | jq
   ```

   See `scripts/logs.sh help` and CLAUDE.md → Debugging Production for
   the full command set.

## Day-to-day

```sh
fly deploy                        # prod
fly deploy -c fly.staging.toml    # staging
fly logs                          # tail logs
fly ssh console                   # shell into the running machine
fly status                        # machine + volume health
```

## Disaster recovery

If the volume is lost or corrupted, the next boot restores automatically
from the Litestream replica (see `rel/overlays/bin/docker-entrypoint`).
To force a restore manually:

```sh
fly ssh console -a bibtime
rm /data/bibtime.db                        # will be rebuilt from replica
exit
fly machine restart <machine-id> -a bibtime
```

To inspect available restore points:

```sh
fly ssh console -a bibtime -C 'litestream snapshots -config /etc/litestream.yml /data/bibtime.db'
```

## Why Litestream instead of managed Postgres

For this workload (modest data volume, low write concurrency, single
region) SQLite + Litestream gives ~1-second RPO at roughly 1/4 to 1/10
the cost of a managed-Postgres equivalent. Restore time is minutes, not
hours, because the DB is small. Revisit this decision if you need read
replicas, cross-region HA, or grow past a few GB.

## Self-hosting alternatives

Fly.io is the path the project is exercised against day-to-day, but
because the entire database is a single SQLite file, BibTime self-hosts
cleanly anywhere a Phoenix release can run. The two paths below are
lighter on infrastructure but skip Litestream — you are responsible for
your own backups (see `scripts/backup.sh`).

### Docker

A `Dockerfile` and `docker-compose.yml` ship in the repo.

```bash
# Generate a secret key (or `openssl rand -base64 64 | tr -d '\n'`
# if you don't have Elixir locally)
export SECRET_KEY_BASE=$(mix phx.gen.secret)

SECRET_KEY_BASE=$SECRET_KEY_BASE PHX_HOST=localhost docker compose up -d
```

The compose file mounts a named volume at `/data`, exposes port 4000,
and wires up a healthcheck against `/healthz`. For a manual run without
compose:

```bash
docker build -t bibtime .

docker run -d \
  --name bibtime \
  -p 4000:4000 \
  -v bibtime_data:/data \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e DATABASE_PATH=/data/bibtime.db \
  -e PHX_HOST=your-domain.com \
  bibtime
```

### Bare metal (systemd)

Build a release on the target machine (Erlang/OTP 28+, Elixir 1.19+,
SQLite3):

```bash
git clone <your-fork> bibtime && cd bibtime
export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix assets.deploy
mix release

sudo mkdir -p /opt/bibtime /var/lib/bibtime
sudo cp -r _build/prod/rel/bibtime/* /opt/bibtime/
sudo useradd --system --home /opt/bibtime --shell /usr/sbin/nologin bibtime
sudo chown bibtime:bibtime /var/lib/bibtime
```

`/etc/systemd/system/bibtime.service`:

```ini
[Unit]
Description=BibTime Race Timing Platform
After=network.target

[Service]
Type=exec
User=bibtime
Group=bibtime
WorkingDirectory=/opt/bibtime
ExecStartPre=/opt/bibtime/bin/migrate
ExecStart=/opt/bibtime/bin/server
Restart=on-failure
RestartSec=5
Environment=PHX_SERVER=true
Environment=DATABASE_PATH=/var/lib/bibtime/bibtime.db
Environment=PHX_HOST=your-domain.com
Environment=PORT=4000
EnvironmentFile=/etc/bibtime/env

[Install]
WantedBy=multi-user.target
```

Put `SECRET_KEY_BASE` (and any optional secrets like `RESEND_API_KEY`,
`STRIPE_SECRET_KEY`) in `/etc/bibtime/env`, owned by root and chmod 600.
Enable with `sudo systemctl enable --now bibtime`.

Front the app with nginx (or any reverse proxy) for TLS termination —
proxy to `127.0.0.1:4000` and forward `Upgrade`/`Connection`,
`X-Forwarded-For`, and `X-Forwarded-Proto` so Phoenix sees the original
scheme and IP.

### Backups (Docker / bare metal)

`scripts/backup.sh` wraps `sqlite3 .backup` so backups are consistent
even while the app is running:

```bash
./scripts/backup.sh backup /var/lib/bibtime/bibtime.db /var/lib/bibtime/backups
./scripts/backup.sh restore /var/lib/bibtime/backups/bibtime_20260321_120000.db /var/lib/bibtime/bibtime.db
```

Schedule via cron, e.g. `0 3 * * * /opt/bibtime/scripts/backup.sh backup …`.
On Fly.io this is unnecessary — Litestream handles continuous replication.

## Health check

`GET /healthz` returns `{"status":"ok"}` with a 200. Used by the
docker-compose healthcheck, by Fly's health probe, and by any external
load balancer or uptime monitor you wire up.

```bash
curl http://localhost:4000/healthz
```

## Environment variables

Read at runtime by `config/runtime.exs`. Anything marked **required**
must be set in `:prod` and `:staging`; the app refuses to boot otherwise.

| Variable                         | Required        | Default              | Description                                                                 |
| -------------------------------- | --------------- | -------------------- | --------------------------------------------------------------------------- |
| `SECRET_KEY_BASE`                | yes             | —                    | 64+ byte cookie/signing secret. Generate with `mix phx.gen.secret`.         |
| `DATABASE_PATH`                  | yes             | —                    | Absolute path to the SQLite file (e.g. `/data/bibtime.db`).                 |
| `PHX_HOST`                       | yes             | —                    | Public hostname for URL generation in emails and meta tags.                 |
| `PHX_SERVER`                     | no              | unset                | Set to `true` to start the web endpoint (set automatically by `bin/server`).|
| `PORT`                           | no              | `4000`               | HTTP port to bind.                                                          |
| `POOL_SIZE`                      | no              | `5`                  | DB connection pool size.                                                    |
| `DNS_CLUSTER_QUERY`              | no              | —                    | DNS query for clustering. Fly sets this automatically.                      |
| `MAILER_FROM_ADDRESS`            | no              | `no-reply@example.com` | `From:` on outbound mail. Must be on a domain verified with your provider.|
| `RESEND_API_KEY`                 | no              | —                    | When set, switches the mailer to Resend. Otherwise mail goes to the local Swoosh adapter (preview at `/dev/mailbox` in staging). |
| `STRIPE_SECRET_KEY`              | no              | —                    | Enables paid registrations.                                                 |
| `STRIPE_WEBHOOK_SECRET`          | required if Stripe enabled | —         | Signing secret for `/webhooks/stripe`.                                      |
| `PHOTO_STORAGE`                  | no              | local disk           | Set to `s3` to store participant photos in an S3-compatible bucket.         |
| `S3_BUCKET` / `BUCKET_NAME`      | required if `PHOTO_STORAGE=s3` | —     | Bucket name. `BUCKET_NAME` is what `fly storage create` injects.            |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION` | required if `PHOTO_STORAGE=s3` | — | S3 credentials. `AWS_REGION` defaults to `us-east-1`.        |
| `AWS_ENDPOINT_URL_S3` / `S3_ENDPOINT_URL` | no     | —                    | Custom S3 endpoint (Tigris, R2, Backblaze, MinIO).                          |
| `DEV_TOOLS_BASIC_AUTH_USERNAME` / `_PASSWORD` | required in `:staging` | — | Guards `/dev/mailbox`, `/dev/dashboard`, `/dev/emails` on staging builds.   |
| `LITESTREAM_*`                   | Fly only        | —                    | See [Provision object storage for Litestream](#4-provision-object-storage-for-litestream). |
