# Deploying BibTime Station to a Raspberry Pi

This is a regular Elixir application that runs as a systemd service on
**Raspberry Pi OS Lite (64-bit)**. The Pi acts as a host for an R200
RFID reader (USB) and posts chip reads to the BibTime server over the
network.

The previous Nerves-based deployment was abandoned because the stock
`nerves_system_rpi0_2` kernel doesn't support USB host mode and is
missing the CH340 / CDC-ECM drivers we need for the R200 and 4G
modems. Pi OS supports all of this out of the box. The application
code is identical either way — only the surrounding OS and deployment
mechanism change.

---

## One-time Pi setup

### 1. Flash the SD card

Use **Raspberry Pi Imager** (https://www.raspberrypi.com/software/) to
write **Raspberry Pi OS Lite (64-bit)** to a microSD card.

Click the gear icon in Imager **before flashing** to set:

- **Hostname**: `bibtime-1` (or `-2`, `-3` for the other stations)
- **Username / password**: pick something memorable
- **WiFi**: SSID + password for the network the Pi will join
- **WiFi country**: `SE`
- **SSH**: enabled, paste your `~/.ssh/id_ed25519.pub` (or whichever
  key) so password-less login works

Flash, eject, plug into the Pi, power on. Give it a minute to boot and
join WiFi.

### 2. Verify SSH access

From your Mac:

```bash
ssh <username>@bibtime-1.local
```

If `bibtime-1.local` doesn't resolve, find the IP from your router's
DHCP table or use `nmap -sn 192.168.1.0/24`.

### 3. Install Erlang and Elixir on the Pi

The Pi Zero 2 W is fast enough to run a full BEAM, and we'll build
the release on the Pi the first time so we don't have to set up
cross-compilation on the Mac.

```bash
# On the Pi
sudo apt update
sudo apt install -y elixir build-essential git
elixir --version    # confirm it works (1.14+ is fine)
```

If apt's Elixir is too old, use `asdf` or download the latest from
elixir-lang.org. For first-light testing the apt version is fine.

### 4. Create the bibtime user and directories

```bash
sudo useradd --system --shell /usr/sbin/nologin --home /opt/bibtime_station bibtime
sudo usermod -aG dialout bibtime    # access to /dev/ttyUSB0

sudo mkdir -p /opt/bibtime_station /var/lib/bibtime_station
sudo chown bibtime:bibtime /opt/bibtime_station /var/lib/bibtime_station
```

### 5. Get the source onto the Pi and build the release

Two ways:

**Option A — git clone (recommended):**

```bash
sudo -u bibtime git clone https://github.com/folsen/bibtime /opt/bibtime_source
cd /opt/bibtime_source/bibtime_station
```

**Option B — scp the source:**

```bash
# On your Mac, from the bibtime repo root
rsync -avz --exclude _build --exclude deps bibtime_station/ \
    pi@bibtime-1.local:/tmp/bibtime_station_source/
# Then on the Pi
sudo mv /tmp/bibtime_station_source /opt/bibtime_source
sudo chown -R bibtime:bibtime /opt/bibtime_source
cd /opt/bibtime_source
```

Then on the Pi:

```bash
sudo -u bibtime mix local.hex --force
sudo -u bibtime mix local.rebar --force
sudo -u bibtime MIX_ENV=prod mix deps.get
sudo -u bibtime MIX_ENV=prod mix release --overwrite

# Unpack the built release into /opt/bibtime_station
sudo -u bibtime tar -xzf _build/prod/bibtime_station-0.1.0.tar.gz \
    -C /opt/bibtime_station
```

The first `mix release` on the Pi takes a few minutes (downloading
deps + compiling Erlang code). Subsequent rebuilds are seconds.

### 6. Install the systemd unit

```bash
# From /opt/bibtime_source/bibtime_station on the Pi
sudo cp deploy/bibtime_station.service /etc/systemd/system/
sudo cp deploy/bibtime_station.env.example /etc/default/bibtime_station
sudo nano /etc/default/bibtime_station
```

Edit `/etc/default/bibtime_station` and set:

- `BIBTIME_URL` to your BibTime server's address (e.g.
  `http://192.168.1.231:4000`). The Phoenix server must be bound to
  `0.0.0.0` not `127.0.0.1` so the Pi can reach it.
- `STATION_TOKEN` to a real token generated in the BibTime admin UI
  (`/admin/races/:id/stations` → create station → copy token)
- `READER_DEVICE` if not `/dev/ttyUSB0` (check `dmesg | tail` after
  plugging the R200 in)

Then:

```bash
sudo systemctl daemon-reload
sudo systemctl enable bibtime_station
sudo systemctl start bibtime_station
sudo systemctl status bibtime_station
```

Logs:

```bash
sudo journalctl -u bibtime_station -f
```

You should see the Reader open `/dev/ttyUSB0`, configure the M100,
start continuous inventory, and the Heartbeat begin posting to the
BibTime server. Check the stations dashboard — your station should
flip to online within ~10 seconds.

---

## Iteration loop

Once the Pi is set up, deploys are fast. From the Pi:

```bash
cd /opt/bibtime_source
git pull              # or rsync the new source over
cd bibtime_station
sudo -u bibtime MIX_ENV=prod mix release --overwrite
sudo -u bibtime tar -xzf _build/prod/bibtime_station-0.1.0.tar.gz \
    -C /opt/bibtime_station
sudo systemctl restart bibtime_station
```

Or wrap it in a deploy script in `deploy/` if you do this often.

For really fast iteration during development, you can also build the
release on your Mac and scp the tarball over — the Erlang runtime in
the release is built for whatever architecture mix release ran on, so
you'd need to be on the same arch (Apple Silicon Mac → aarch64 Pi
both work, since the Pi Zero 2 W is aarch64). If you hit
incompatibilities, build on the Pi.

---

## Hardware

### R200 over USB

Plug the R200 into the Pi's USB OTG port via a micro-USB OTG adapter.
The CH340 USB-serial chip on the dev board is supported by the stock
Pi OS kernel — it'll show up as `/dev/ttyUSB0` in `dmesg`. The R200
draws ~300mA peak; the Pi's USB port can usually supply this but a
**powered USB hub** between the Pi and the R200 is more reliable,
especially if you also want to plug in a USB 4G modem alongside.

### R200 + 4G modem via a powered USB hub

The Pi Zero 2 W has only one USB port. To run both the R200 and a USB
modem (or any other USB peripheral), use a **powered USB hub**:

```
Power bank ──┬── micro-USB cable ──► Pi PWR port
             │
             └── USB cable ──► Powered USB hub (DC input)
                                      │
                                      ├── USB-A to micro-USB ──► R200
                                      ├── USB-A to USB-C ──────► 4G modem
                                      └── USB OTG to Pi ────────► Pi data USB
```

The hub powers the peripherals from its DC input; the Pi powers
itself from a separate output of the same power bank.

Pick a hub that takes **5V input** (USB-C or micro-USB power input)
so it can run from a power bank. Many cheap hubs use a 12V wall wart
which won't work in the field.

### Network options

- **WiFi (Pi OS)**: Configured during the Imager flash. No code or
  config in this project — set the SSID at provision time.
- **Phone hotspot**: Works the same way. Configure the hotspot SSID
  in Imager and the Pi joins automatically.
- **USB 4G modem (CDC-ECM)**: Plug in via the powered hub. Pi OS
  detects it as a USB ethernet device (`usb0` or `wwan0`) and
  configures DHCP automatically. No code changes needed.
- **4G HAT (UART)**: Plug onto the GPIO header. The HAT will use
  GPIO 14/15 and appear as `/dev/ttyAMA0`. Keep the R200 on USB
  (`/dev/ttyUSB0`) so they don't conflict.

---

## Troubleshooting

### `Failed to start bibtime_station.service`

```bash
sudo journalctl -u bibtime_station --since "10 minutes ago"
```

Common causes:
- `BIBTIME_URL` or `STATION_TOKEN` missing → see the runtime.exs
  `raise` messages in the log
- `/dev/ttyUSB0` doesn't exist → R200 isn't plugged in or plugged
  into a different port
- bibtime user not in `dialout` group → permission denied on serial

### Reader keeps logging `could not open /dev/ttyUSB0: :enoent`

The R200 isn't visible. Check:

```bash
ls /dev/ttyUSB*
dmesg | grep -i ch341
dmesg | grep -i usb
```

If the CH340 attaches successfully you'll see something like:
```
ch341 1-1.2:1.0: ch341-uart converter detected
usb 1-1.2: ch341-uart converter now attached to ttyUSB0
```

If you see the device but at a different path (e.g. `ttyUSB1`),
update `READER_DEVICE` in `/etc/default/bibtime_station`.

### Station never appears in BibTime dashboard

The Heartbeat tries every 10 seconds. If it's not landing:

```bash
# From the Pi, manually try the heartbeat URL:
curl -i -X PUT \
    "$BIBTIME_URL/api/stations/$STATION_TOKEN/heartbeat" \
    -H "Content-Type: application/json" \
    -d '{"firmware_version":"manual","reads_total":0,"buffer_size":0,"uptime_seconds":0,"reader_connected":true}'
```

- 200 → server is reachable, station exists, problem is local to the
  application (check journalctl)
- 401 → token mismatch (check the admin UI vs `/etc/default/...`)
- `connection refused` → BibTime server not bound to a routable IP,
  or the Pi can't reach the BibTime host. Check `BIBTIME_URL` is the
  Mac's LAN IP (not localhost) and that Phoenix's `dev.exs` binds to
  `{0, 0, 0, 0}` not `{127, 0, 0, 1}`.
