#!/usr/bin/env bash
#
# fix-ch340-usb.sh — Rebind CH340 USB-serial adapter if its probe failed.
#
# On cold boot the CH340 sometimes fails with EPROTO (-71) because the
# USB bus isn't fully stable yet (common when a hub powers the Pi and
# peripherals simultaneously). The kernel detects the chip but the
# driver probe fails, so /dev/ttyUSB* is never created.
#
# This script checks for that situation and forces a driver unbind/rebind
# which re-runs the probe. It retries a few times with short delays to
# give the bus time to settle.
#
# Intended to run as ExecStartPre in the bibtime_station systemd unit.

set -euo pipefail

DEVICE="${READER_DEVICE:-/dev/ttyUSB0}"
MAX_RETRIES=5
RETRY_DELAY=2

# If the device already exists, nothing to do.
if [ -e "$DEVICE" ]; then
  echo "fix-ch340-usb: $DEVICE already present, OK"
  exit 0
fi

echo "fix-ch340-usb: $DEVICE missing, looking for failed CH340 device..."

rebind_ch340() {
  # Find CH340 interfaces bound to the ch341 driver.
  local driver_path="/sys/bus/usb/drivers/ch341"
  if [ ! -d "$driver_path" ]; then
    echo "fix-ch340-usb: ch341 driver not loaded, skipping rebind"
    return 1
  fi

  for iface in "$driver_path"/[0-9]*; do
    [ -e "$iface" ] || continue
    local iface_name
    iface_name="$(basename "$iface")"
    echo "fix-ch340-usb: rebinding $iface_name..."
    echo "$iface_name" > "$driver_path/unbind" 2>/dev/null || true
    sleep 0.5
    echo "$iface_name" > "$driver_path/bind" 2>/dev/null || true
    return 0
  done

  # No bound interfaces found — try rebinding at the USB device level.
  # Look for the CH340 vendor:product (1a86:7523) in sysfs.
  for devpath in /sys/bus/usb/devices/*/idVendor; do
    [ -e "$devpath" ] || continue
    local dir
    dir="$(dirname "$devpath")"
    local vendor product
    vendor="$(cat "$dir/idVendor" 2>/dev/null)" || continue
    product="$(cat "$dir/idProduct" 2>/dev/null)" || continue
    if [ "$vendor" = "1a86" ] && [ "$product" = "7523" ]; then
      local devname
      devname="$(basename "$dir")"
      echo "fix-ch340-usb: found CH340 at $devname, rebinding USB device..."
      echo "$devname" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null || true
      sleep 0.5
      echo "$devname" > /sys/bus/usb/drivers/usb/bind 2>/dev/null || true
      return 0
    fi
  done

  echo "fix-ch340-usb: no CH340 device found in sysfs"
  return 1
}

for i in $(seq 1 "$MAX_RETRIES"); do
  if [ -e "$DEVICE" ]; then
    echo "fix-ch340-usb: $DEVICE appeared after rebind, OK"
    exit 0
  fi

  echo "fix-ch340-usb: attempt $i/$MAX_RETRIES..."
  rebind_ch340 || true
  sleep "$RETRY_DELAY"
done

# Final check
if [ -e "$DEVICE" ]; then
  echo "fix-ch340-usb: $DEVICE appeared, OK"
  exit 0
fi

echo "fix-ch340-usb: WARNING — $DEVICE still missing after $MAX_RETRIES attempts."
echo "fix-ch340-usb: the station service will start anyway and retry on its own."
# Exit 0 so the service still starts — the Reader GenServer retries internally.
exit 0
