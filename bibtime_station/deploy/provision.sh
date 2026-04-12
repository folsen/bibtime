#!/usr/bin/env bash
#
# Provision a freshly-flashed Raspberry Pi for BibTime Station.
#
# Usage:
#   ./deploy/provision.sh <hostname>
#
# Example:
#   ./deploy/provision.sh bibtime-1.local
#
# Prerequisites:
#   - Pi is running Raspberry Pi OS Lite (64-bit)
#   - SSH key auth is already configured (done via Imager)
#   - Pi username is "bibtime" (set in Imager)
#   - Pi is reachable at the given hostname
#
# What this does:
#   1. Installs Erlang + Elixir + build-essential via apt
#   2. Adds the bibtime user to the dialout group (for serial access)
#   3. Creates /opt/bibtime_station and /var/lib/bibtime_station
#   4. Installs the systemd unit file
#   5. Copies the env template to /etc/default/bibtime_station
#   6. Installs hex + rebar
#
# After provisioning, edit /etc/default/bibtime_station on the Pi to
# set BIBTIME_URL and STATION_TOKEN, then run deploy.sh to push code.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <hostname>"
  echo "Example: $0 bibtime-1.local"
  exit 1
fi

HOST="bibtime@$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Provisioning $1 (user: bibtime)"

echo "--- Installing system packages (Erlang, Elixir, build-essential)..."
ssh "$HOST" "sudo apt update -qq && sudo apt install -y -qq elixir erlang-dev build-essential"

echo "--- Setting up directories and permissions..."
ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

sudo usermod -aG dialout bibtime

sudo mkdir -p /opt/bibtime_station /opt/bibtime_source /var/lib/bibtime_station
sudo chown bibtime:bibtime /opt/bibtime_station /opt/bibtime_source /var/lib/bibtime_station
REMOTE

echo "--- Installing systemd service and env template..."
scp "$SCRIPT_DIR/bibtime_station.service" "$HOST:/tmp/bibtime_station.service"
scp "$SCRIPT_DIR/bibtime_station.env.example" "$HOST:/tmp/bibtime_station.env"

ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

sudo cp /tmp/bibtime_station.service /etc/systemd/system/bibtime_station.service

# Only copy env template if the real config doesn't exist yet
if [ ! -f /etc/default/bibtime_station ]; then
  sudo cp /tmp/bibtime_station.env /etc/default/bibtime_station
  echo "Created /etc/default/bibtime_station — edit it to set BIBTIME_URL and STATION_TOKEN"
else
  echo "/etc/default/bibtime_station already exists, skipping"
fi

rm -f /tmp/bibtime_station.service /tmp/bibtime_station.env

sudo systemctl daemon-reload
sudo systemctl enable bibtime_station

# Enable GPIO3 power button (clean shutdown on press, wake on press when halted)
if ! grep -q 'gpio-shutdown' /boot/firmware/config.txt 2>/dev/null; then
  echo 'dtoverlay=gpio-shutdown,gpio_pin=3' | sudo tee -a /boot/firmware/config.txt >/dev/null
  echo "Enabled gpio-shutdown overlay (GPIO3 power button)"
else
  echo "gpio-shutdown overlay already configured"
fi
REMOTE

echo "--- Installing hex and rebar..."
ssh "$HOST" "mix local.hex --force && mix local.rebar --force"

echo ""
echo "==> Provisioning complete!"
echo ""
echo "Next steps:"
echo "  1. SSH into the Pi and edit /etc/default/bibtime_station"
echo "     ssh $HOST"
echo "     sudo nano /etc/default/bibtime_station"
echo ""
echo "  2. Set BIBTIME_URL and STATION_TOKEN"
echo ""
echo "  3. Run the deploy script to push and build the code:"
echo "     ./deploy/deploy.sh $1"
