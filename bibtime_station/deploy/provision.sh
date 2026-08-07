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
#   7. Installs Tailscale and joins the tailnet (prompts for an auth
#      key — generate a reusable, pre-authorized key tagged
#      tag:station in the Tailscale admin; press Enter to skip)
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

echo "--- Installing systemd service, env template, and USB fix script..."
scp "$SCRIPT_DIR/bibtime_station.service" "$HOST:/tmp/bibtime_station.service"
scp "$SCRIPT_DIR/bibtime_station.env.example" "$HOST:/tmp/bibtime_station.env"
scp "$SCRIPT_DIR/fix-ch340-usb.sh" "$HOST:/tmp/fix-ch340-usb.sh"

ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

sudo cp /tmp/bibtime_station.service /etc/systemd/system/bibtime_station.service

# USB fix script — runs as ExecStartPre to rebind CH340 if probe failed on boot
sudo cp /tmp/fix-ch340-usb.sh /opt/bibtime_station/fix-ch340-usb.sh
sudo chmod +x /opt/bibtime_station/fix-ch340-usb.sh

# Only copy env template if the real config doesn't exist yet
if [ ! -f /etc/default/bibtime_station ]; then
  sudo cp /tmp/bibtime_station.env /etc/default/bibtime_station
  echo "Created /etc/default/bibtime_station — edit it to set BIBTIME_URL and STATION_TOKEN"
else
  echo "/etc/default/bibtime_station already exists, skipping"
fi

rm -f /tmp/bibtime_station.service /tmp/bibtime_station.env /tmp/fix-ch340-usb.sh

sudo systemctl daemon-reload
sudo systemctl enable bibtime_station

# 4G modem (eth0/usb0) is backup connectivity only: demote its default
# route below wlan0 and never use its DNS — a modem whose data service
# drops otherwise hijacks the default route and blackholes everything
# while WiFi sits idle.
sudo tee /etc/netplan/95-modem-backup.yaml > /dev/null <<'NETPLAN'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 700
        use-dns: false
      dhcp6: true
      optional: true
NETPLAN
sudo chmod 600 /etc/netplan/95-modem-backup.yaml
sudo netplan apply 2>/dev/null || true
echo "Installed modem-backup netplan drop-in (eth0 route metric 700, DNS ignored)"

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

echo "--- Installing Tailscale..."
ssh "$HOST" bash <<'REMOTE'
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled
REMOTE

# Tailnet hostname = provisioning hostname minus any .local suffix, so
# MagicDNS names line up with how we already address the Pis.
TS_HOSTNAME="${1%%.*}"

if ssh "$HOST" "tailscale status >/dev/null 2>&1"; then
  echo "--- Tailscale already up on $TS_HOSTNAME, skipping join"
else
  # The key can be supplied via the TS_AUTHKEY env var (e.g. from .env)
  # for non-interactive runs; otherwise prompt when on a terminal.
  if [ -z "${TS_AUTHKEY:-}" ] && [ -t 0 ]; then
    echo ""
    echo "Paste the station auth key from the password manager entry"
    echo "'tailscale-station-authkey' (or press Enter to skip Tailscale)."
    read -rsp "Tailscale auth key (tskey-auth-...): " TS_AUTHKEY
    echo
  fi
  TS_AUTHKEY="${TS_AUTHKEY:-}"

  if [ -n "$TS_AUTHKEY" ]; then
    ssh "$HOST" sudo tailscale up \
      --authkey="$TS_AUTHKEY" \
      --ssh \
      --hostname="$TS_HOSTNAME" \
      --advertise-tags=tag:station \
      --accept-dns=false
    echo "--- Tailscale up as $TS_HOSTNAME"
  else
    echo "--- Skipped Tailscale join (run 'sudo tailscale up ...' on the Pi later)"
  fi
fi

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
