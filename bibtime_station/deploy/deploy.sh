#!/usr/bin/env bash
#
# Deploy BibTime Station to a provisioned Raspberry Pi.
#
# Usage:
#   ./deploy/deploy.sh <hostname>
#
# Example:
#   ./deploy/deploy.sh bibtime-1.local
#
# What this does:
#   1. Rsync the bibtime_station source to /opt/bibtime_source on the Pi
#   2. Fetch deps (if needed) and build a prod release
#   3. Unpack the release into /opt/bibtime_station
#   4. Restart the systemd service
#
# Prerequisites:
#   - Pi has been provisioned with provision.sh
#   - /etc/default/bibtime_station has been configured

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <hostname>"
  echo "Example: $0 bibtime-1.local"
  exit 1
fi

HOST="bibtime@$1"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying bibtime_station to $1"

echo "--- Syncing source to Pi..."
rsync -az --delete \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.elixir_ls' \
  "$PROJECT_DIR/" "$HOST:/opt/bibtime_source/"

echo "--- Building release on Pi..."
ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

cd /opt/bibtime_source
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release --overwrite

echo "--- Unpacking release..."
tar -xzf _build/prod/bibtime_station-*.tar.gz -C /opt/bibtime_station
REMOTE

echo "--- Restarting service..."
ssh "$HOST" "sudo systemctl restart bibtime_station"

echo "--- Waiting for service to start..."
ssh "$HOST" "sleep 2 && sudo systemctl status bibtime_station --no-pager -l" || true

echo ""
echo "==> Deploy complete! Tail logs with:"
echo "    ssh $HOST sudo journalctl -u bibtime_station -f"
