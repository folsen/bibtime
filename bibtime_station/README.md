# BibTime Station

Elixir application that runs on a Raspberry Pi at a race timing point.
Reads RFID tags from an R200 (M100) reader over a serial port,
deduplicates them, and POSTs them to the BibTime server. Maintains a
local offline buffer if the network drops, and sends periodic
heartbeats so the server-side dashboard knows the station is alive.

## Architecture

```
┌─────────────────────────────────────────┐
│  BibtimeStation OTP application         │
│                                         │
│  Buffer  ──┐                            │
│            │                            │
│  Reader ───┼──► ReadPipeline ──► Uplink │
│            │     (dedup +         │     │
│  Heartbeat │      counter)        │     │
│            │                      ▼     │
│            └─────────────────► HTTP     │
│                                         │
└─────────────────────────────────────────┘
                                  │
                                  ▼
                          BibTime server
                          /api/stations/...
```

`rest_for_one` supervision: a `Reader` crash restarts everything
downstream; `Buffer` is the root so any restart catches it.

## Hardware

- **Raspberry Pi Zero 2 W** running **Raspberry Pi OS Lite (64-bit)**
- **Invelion R200 dev board** (actually an M100, see
  `../hardware/R200_PROTOCOL.md`)
- UHF antenna
- USB OTG adapter, optionally a powered USB hub for powering the
  R200 reliably alongside other USB peripherals (e.g. a 4G modem)

## Development (Mac)

```bash
mix deps.get
mix test                       # 29 tests, no hardware needed
mix test --only hardware       # talks to a real R200 plugged into the Mac
iex -S mix                     # interactive shell, supervisor not auto-started
```

To bring up the full pipeline against the R200 in a dev iex session:

```elixir
Application.put_env(:bibtime_station, :start_supervision_tree, true)
{:ok, _} = Application.ensure_all_started(:bibtime_station)
```

The `dev.exs` config points at `/dev/cu.usbserial-11330` — update it
if your Mac enumerates the R200 at a different path.

## Production (Pi)

See **[DEPLOYMENT.md](DEPLOYMENT.md)** for the full Pi setup
walkthrough: flashing Pi OS, installing Elixir, building the release
on the Pi, installing the systemd unit, and configuring per-station
secrets via `/etc/default/bibtime_station`.

## Configuration

Environment variables read at runtime by `config/runtime.exs` (prod
only):

| Variable | Purpose | Example |
|---|---|---|
| `BIBTIME_URL` | BibTime server base URL | `http://192.168.1.231:4000` |
| `STATION_TOKEN` | Per-station auth token | (from admin UI) |
| `READER_DEVICE` | Serial port | `/dev/ttyUSB0` |
| `BUFFER_PATH` | DETS file location | `/var/lib/bibtime_station/read_buffer.dets` |

Compile-time defaults are in `config/config.exs` and overridden by
the per-environment files.
