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
