# BibTime Deployment Guide

BibTime is designed for easy self-hosting. It uses SQLite, so there's no external database to manage — your entire database is a single file.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SECRET_KEY_BASE` | **Yes** (prod) | — | 64+ byte secret for signing cookies. Generate with `mix phx.gen.secret` |
| `DATABASE_PATH` | **Yes** (prod) | — | Absolute path to the SQLite database file (e.g. `/data/bibtime.db`) |
| `PHX_HOST` | **Yes** (prod) | `example.com` | Public hostname for URL generation |
| `PHX_SERVER` | No | — | Set to `true` to start the web server (set automatically by `bin/server`) |
| `PORT` | No | `4000` | HTTP port to listen on |
| `POOL_SIZE` | No | `5` | Database connection pool size |
| `DNS_CLUSTER_QUERY` | No | — | DNS query for clustering (Fly.io sets this automatically) |

## Option 1: Docker

The simplest way to run BibTime.

### Quick Start

```bash
# Generate a secret key
export SECRET_KEY_BASE=$(mix phx.gen.secret)

# Or without Elixir installed:
# export SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')

# Start with docker compose
SECRET_KEY_BASE=$SECRET_KEY_BASE PHX_HOST=localhost docker compose up -d
```

BibTime will be available at `http://localhost:4000`.

### Build and Run Manually

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

## Option 2: Fly.io

One-click deployment to Fly.io with persistent storage.

### Prerequisites

Install the [Fly CLI](https://fly.io/docs/flyctl/install/) and log in:

```bash
fly auth login
```

### Deploy

```bash
# Create the app (uses the included fly.toml)
fly launch --no-deploy

# Create a persistent volume for the database
fly volumes create bibtime_data --region arn --size 1

# Set the secret key
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)

# Set your hostname
fly secrets set PHX_HOST=your-app.fly.dev

# Deploy
fly deploy
```

The `fly.toml` is pre-configured with:
- `arn` (Stockholm) as the primary region
- A release command that runs migrations automatically
- Health checks on `/healthz`
- Auto-stop/start for cost savings
- Persistent volume mounted at `/data`

### Backups on Fly.io

```bash
# SSH into the machine
fly ssh console

# Run a backup inside the container
sqlite3 /data/bibtime.db ".backup /data/bibtime_backup.db"

# Or download the database locally
fly ssh sftp get /data/bibtime.db ./bibtime_backup.db
```

## Option 3: Bare Metal (systemd)

For running directly on a Linux server.

### Prerequisites

- Erlang/OTP 28+
- Elixir 1.19+
- SQLite3

### Build the Release

```bash
# Clone and build
git clone https://github.com/your-org/bibtime.git
cd bibtime

export MIX_ENV=prod
mix deps.get --only prod
mix compile
mix assets.deploy
mix release
```

### Install

```bash
# Copy release to /opt
sudo mkdir -p /opt/bibtime
sudo cp -r _build/prod/rel/bibtime/* /opt/bibtime/

# Create data directory
sudo mkdir -p /var/lib/bibtime
sudo chown bibtime:bibtime /var/lib/bibtime
```

### Create a systemd Service

Create `/etc/systemd/system/bibtime.service`:

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
Environment=MIX_ENV=prod
Environment=PHX_SERVER=true
Environment=DATABASE_PATH=/var/lib/bibtime/bibtime.db
Environment=PHX_HOST=your-domain.com
Environment=PORT=4000
# Load secret from a file
EnvironmentFile=/etc/bibtime/env

[Install]
WantedBy=multi-user.target
```

Create `/etc/bibtime/env` (readable only by root and the service user):

```bash
SECRET_KEY_BASE=your-generated-secret-here
```

### Start the Service

```bash
# Create the system user
sudo useradd --system --home /opt/bibtime --shell /usr/sbin/nologin bibtime

# Set permissions
sudo chmod 600 /etc/bibtime/env

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable bibtime
sudo systemctl start bibtime

# Check status
sudo systemctl status bibtime
sudo journalctl -u bibtime -f
```

### Reverse Proxy (nginx)

Put BibTime behind nginx for SSL termination:

```nginx
upstream bibtime {
    server 127.0.0.1:4000;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://bibtime;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Backup & Restore

Use the included backup script for safe SQLite backups (works even while the app is running):

```bash
# Create a backup
./scripts/backup.sh backup /data/bibtime.db ./backups

# Restore from backup (stops and backs up existing DB first)
./scripts/backup.sh restore ./backups/bibtime_20260321_120000.db /data/bibtime.db
```

### Automated Backups (cron)

```cron
# Daily backup at 3 AM
0 3 * * * /opt/bibtime/scripts/backup.sh backup /var/lib/bibtime/bibtime.db /var/lib/bibtime/backups
```

## Health Check

BibTime exposes a `/healthz` endpoint that returns `{"status":"ok"}` with a 200 status code. This is used by Docker, Fly.io, and load balancers to verify the application is running.

```bash
curl http://localhost:4000/healthz
# {"status":"ok"}
```

## First-Time Setup

After deploying, visit your BibTime instance and create an account. The first user registered via the seeds or direct DB access should be promoted to admin. If you're using Docker or a fresh deployment, the seed data creates a default admin user — check `priv/repo/seeds.exs` for the credentials.
