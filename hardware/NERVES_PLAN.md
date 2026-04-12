# Nerves Timing Station — Implementation Plan

Plan for building a Nerves firmware for the Raspberry Pi Zero 2 W timing stations, and the corresponding server-side changes in BibTime.

---

## Architecture Overview

```
┌──────────────────────────────────────┐         ┌──────────────────────────────┐
│  Timing Station (Nerves on Pi)       │         │  BibTime Server (Phoenix)    │
│                                      │         │                              │
│  ┌────────────┐   ┌──────────────┐   │  HTTP   │  ┌────────────────────────┐  │
│  │ R200Reader │──►│ ReadPipeline │────────────────►│ POST /api/stations/    │  │
│  │ (GenServer)│   │ dedup +      │   │         │  │      :token/reads      │  │
│  │ USB serial │   │ timestamp    │   │         │  │                        │  │
│  └────────────┘   └──────┬───────┘   │         │  │ Timing.ingest_chip_    │  │
│                          │           │         │  │ read/2                 │  │
│                   ┌──────▼───────┐   │         │  │  ├ lookup participant  │  │
│                   │ Uplink       │   │         │  │  ├ record split_time   │  │
│                   │ (GenServer)  │   │         │  │  └ broadcast PubSub    │  │
│                   │ POST to API  │   │         │  └────────────────────────┘  │
│                   │ retry+backoff│   │         │                              │
│                   └──────┬───────┘   │         │  ┌────────────────────────┐  │
│                          │           │         │  │ PUT /api/stations/     │  │
│                   ┌──────▼───────┐   │         │  │     :token/heartbeat   │  │
│                   │ Buffer       │   │  HTTP   │  │                        │  │
│                   │ (DETS/disk)  │────────────────►│ Updates station status │  │
│                   │ offline queue│   │         │  │ last_seen_at, stats    │  │
│                   └──────────────┘   │         │  └────────────────────────┘  │
│                                      │         │                              │
│  ┌────────────┐                      │         │  ┌────────────────────────┐  │
│  │ Heartbeat  │ status, read count,  │         │  │ StationMonitorLive    │  │
│  │ (periodic) │ signal, uptime  ─────────────────►│ live dashboard of all  │  │
│  └────────────┘                      │         │  │ connected stations     │  │
│                                      │         │  └────────────────────────┘  │
│  ┌────────────┐                      │         │                              │
│  │ StatusLED  │ blink patterns for   │         │                              │
│  │ (optional) │ connected/reading/err│         │                              │
│  └────────────┘                      │         │                              │
└──────────────────────────────────────┘         └──────────────────────────────┘
```

### Key design decisions

**The station is a dumb reader.** It reads chip_ids and timestamps, and ships them to the server. It does not know about participants, splits, races, or elapsed times. BibTime does all the business logic. This keeps the firmware simple and means split assignment, participant lookup, and race configuration can change on the server without touching the stations.

**No shared hex package needed.** The station talks to BibTime over a simple JSON HTTP API. The "contract" is a few JSON fields. Extracting shared Elixir code into a hex package would add build/release complexity for no real benefit at this stage.

**USB serial first.** The plan uses `/dev/ttyUSB0` (USB connection via OTG adapter). If we later switch to UART (Option B in HARDWARE_SETUP.md), the only change is the device path (`/dev/ttyAMA0`) and a config flag — `circuits_uart` handles both identically.

> **Note on UART vs USB:** The GenServer design is identical either way. If initial testing shows USB power is insufficient or unreliable, switching to UART is a one-line config change (`device: "/dev/ttyAMA0"` instead of `device: "/dev/ttyUSB0"`). The UART option would slightly simplify the Nerves firmware since we wouldn't need USB gadget/host configuration, but it's not a meaningful difference in the software.

---

## Phase 1: R200 Serial Protocol Discovery — DONE ✓

Protocol findings are documented in [R200_PROTOCOL.md](R200_PROTOCOL.md). Key findings:

- **The board is actually an M100** (firmware V2.3.5), not a true ThingMagic R200. Reports as `M100 26dBm V1.0` to the version command.
- **Frame format is non-standard**: `AA` header, `DD` end marker (NOT `BB`/`7E`).
- **Settings**: 115200 baud, 8N1, no flow control, DTR=False, RTS=False.
- **CH340 quirk on macOS**: needs a brief 9600-baud "wake" before opening at 115200. May not be needed on Linux/Pi — verify during Nerves development.
- **Tag reads work**: confirmed at ~36 reads/sec for a single tag held near the antenna.
- **Default region was China (0x03)**, switched to EU (0x02) via cmd 0x07.
- **Default power was 26 dBm (max)**, set to 20 dBm via cmd 0xB6.

This protocol is simple enough to implement directly in Elixir using `circuits_uart` — no port to a C library needed.

---

## Phase 2: BibTime Server — Station API

Add the HTTP API that timing stations will call. This is all server-side Phoenix work in the existing BibTime repo.

### 2.1 TimingStation schema and context

New schema: `Bibtime.Timing.TimingStation`

```elixir
schema "timing_stations" do
  field :name, :string              # "Station 1 — Finish Line"
  field :token, :string             # auth token (generated, unique)
  field :status, Ecto.Enum,
    values: [:offline, :online, :reading, :error]
  field :last_seen_at, :utc_datetime
  field :firmware_version, :string
  field :serial_number, :string     # Pi serial or custom identifier
  field :metadata, :map             # reads_total, signal_strength, uptime, etc.

  belongs_to :race, Bibtime.Races.Race
  belongs_to :split, Bibtime.Races.Split  # which split point this station covers

  timestamps()
end
```

**Migration:** `mix ecto.gen.migration create_timing_stations`

**Context functions** in `Bibtime.Timing`:

```elixir
def create_timing_station(race, split, attrs)
def get_station_by_token(token)
def update_station_heartbeat(station, metadata)
def list_stations_for_race(race_id)
```

### 2.2 API controller

New controller: `BibtimeWeb.API.StationController`

**Endpoints:**

```
POST   /api/stations/:token/reads
  Body: {"chip_id": "E200...", "read_at": "2026-06-15T09:23:45.123Z", "rssi": -45, "read_count": 3}
  → 200 {status: "recorded", participant_bib: "42", participant_name: "Anna Svensson"}
  → 200 {status: "duplicate"}     (same chip+split within dedup window)
  → 200 {status: "unmatched"}     (chip_id not assigned to any participant)
  → 401 Unauthorized              (bad token)

PUT    /api/stations/:token/heartbeat
  Body: {"firmware_version": "0.1.0", "reads_total": 847, "uptime_seconds": 14400, ...}
  → 200 OK

POST   /api/stations/:token/reads/batch
  Body: {"reads": [{...}, {...}]}  (for flushing offline buffer)
  → 200 {results: [{status: "recorded"}, {status: "duplicate"}, ...]}
```

**Auth:** Token-based, no user session. The token is generated when creating the station in the admin UI and baked into the station's firmware config. Simple and stateless — no login flow needed on the Pi.

### 2.3 Chip read ingestion

New function: `Bibtime.Timing.ingest_chip_read/2`

This is the core function that processes a raw chip read from a station:

```elixir
def ingest_chip_read(station, %{"chip_id" => chip_id, "read_at" => read_at} = raw) do
  race_id = station.race_id
  split_id = station.split_id

  with {:ok, participant} <- lookup_participant(race_id, chip_id),
       :ok <- check_not_duplicate(participant, split_id),
       {:ok, elapsed_ms} <- calculate_elapsed(race_id, read_at),
       {:ok, split_time} <- record_split_time(%{
         participant_id: participant.id,
         split_id: split_id,
         elapsed_ms: elapsed_ms,
         absolute_time: read_at,
         source: :chip,
         raw_chip_data: Jason.encode!(raw)
       }) do
    {:ok, :recorded, participant}
  else
    {:error, :no_participant} -> {:ok, :unmatched}
    {:error, :duplicate} -> {:ok, :duplicate}
    {:error, reason} -> {:error, reason}
  end
end
```

Key points:
- The station's assigned `split_id` determines which split the read goes to. The station doesn't need to know.
- `calculate_elapsed/2` uses `RaceStart.started_at` for the race to compute `elapsed_ms`.
- Duplicates (same participant + split already recorded) return `:duplicate` — not an error.
- Unmatched chips (tag not assigned to any participant) return `:unmatched` so the station can log it, but it's not an error.
- The existing PubSub broadcast in `record_split_time/1` fires automatically, so the admin timing UI updates in real time.

### 2.4 Station management UI

New LiveView: `BibtimeWeb.Admin.StationLive.Index`

Route: `/admin/races/:id/stations`

Features:
- List all stations for a race with live status indicators (green/yellow/red dot)
- Create new station: pick a name, assign to a split, generate auth token
- Show token + QR code for easy firmware provisioning
- Live-updating stats per station: reads total, last read, last heartbeat
- Alert when a station goes offline (no heartbeat for >30 seconds)

PubSub topic: `"race:stations:#{race_id}"` for station status updates.

---

## Phase 3: Nerves Firmware — Project Setup

### 3.1 Create the Nerves project

```bash
# From the bibtime repo root (or a sibling directory — see note below)
mix nerves.new bibtime_station --target rpi0_2
cd bibtime_station
```

**Where to put the project:** Two options:

- **Subdirectory** (`bibtime/bibtime_station/`): Keeps everything in one repo. Simple. But Nerves projects have their own mix.exs and deps, so it's not an umbrella — it's a standalone project that happens to live in the same repo.
- **Separate repo** (`bibtime-station/`): Cleaner separation. Independent CI. Makes more sense long-term.

Recommendation: **Start as a subdirectory** for convenience during development, move to a separate repo later if needed.

### 3.2 Key dependencies

```elixir
# mix.exs
defp deps do
  [
    # Nerves core
    {:nerves, "~> 1.10", runtime: false},
    {:nerves_system_rpi0_2, "~> 1.27", runtime: false, targets: :rpi0_2},
    {:nerves_runtime, "~> 0.13"},
    {:nerves_pack, "~> 0.7"},      # includes WiFi, SSH, NTP, mDNS

    # Serial communication
    {:circuits_uart, "~> 1.5"},

    # HTTP client (for posting reads to BibTime)
    {:req, "~> 0.5"},

    # Local buffer (offline reads)
    # DETS is built into OTP — no extra dep needed
    # Or use {:cubdb, "~> 2.0"} for a more robust embedded KV store

    # JSON
    {:jason, "~> 1.4"},

    # Logging
    {:ring_logger, "~> 0.10"},

    # Development
    {:toolshed, "~> 0.4"},        # helpful IEx utilities on the device
  ]
end
```

### 3.3 Configuration

```elixir
# config/target.exs (on-device config)
config :bibtime_station,
  bibtime_url: "http://192.168.1.100:4000",  # or mDNS: "http://bibtime.local:4000"
  station_token: "generated-token-from-admin-ui",
  reader_device: "/dev/ttyUSB0",
  reader_baud: 115200,
  read_dedup_window_ms: 5_000,     # ignore same tag within 5 seconds
  heartbeat_interval_ms: 10_000,   # send heartbeat every 10 seconds
  read_power: 2000                 # centidBm, start conservative

# WiFi
config :vintage_net,
  regulatory_domain: "SE",
  config: [
    {"wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [%{ssid: "race-wifi", psk: "password", key_mgmt: :wpa_psk}]
      },
      ipv4: %{method: :dhcp}
    }}
  ]
```

### 3.4 Firmware build and deploy

```bash
# Build (from host machine, e.g. macOS)
export MIX_TARGET=rpi0_2
mix deps.get
mix firmware

# First install: burn to SD card
mix firmware.burn

# Subsequent updates: push over SSH
mix upload timing-station-1.local
```

---

## Phase 4: Nerves Firmware — Application Modules

### 4.1 Supervision tree

```elixir
defmodule BibtimeStation.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Offline read buffer (DETS table)
      BibtimeStation.Buffer,

      # Reads from R200 serial, emits {:tag_read, chip_id, rssi, timestamp}
      BibtimeStation.Reader,

      # Receives tag reads, deduplicates, dispatches to Uplink
      BibtimeStation.ReadPipeline,

      # POSTs reads to BibTime API, retries on failure, flushes buffer
      BibtimeStation.Uplink,

      # Periodic heartbeat to BibTime API
      BibtimeStation.Heartbeat,
    ]

    opts = [strategy: :rest_for_one, name: BibtimeStation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

`rest_for_one` strategy: if the Reader crashes, everything downstream restarts. If Uplink crashes, only Uplink and Heartbeat restart. Buffer is first so it's always available.

### 4.2 BibtimeStation.Reader

The Reader speaks the M100/Invelion protocol over `circuits_uart`. Frame format documented in [R200_PROTOCOL.md](R200_PROTOCOL.md).

```elixir
defmodule BibtimeStation.Reader do
  use GenServer
  alias Circuits.UART
  alias BibtimeStation.Reader.Protocol

  # Opens the serial port and continuously reads tags.
  # Sends {:tag_read, %{chip_id, rssi, read_count, timestamp}} to ReadPipeline.
  #
  # On serial errors, crashes and lets the supervisor restart it
  # (which re-opens the serial port).

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    device = Application.get_env(:bibtime_station, :reader_device)
    baud = Application.get_env(:bibtime_station, :reader_baud)

    {:ok, uart} = UART.start_link()
    :ok = UART.open(uart, device, speed: baud, active: true,
                    framing: {Protocol.Framer, []})  # custom framer for AA...DD

    # Configure reader: region, power
    UART.write(uart, Protocol.set_region(:eu))
    UART.write(uart, Protocol.set_power(2000))  # 20 dBm in centidBm

    # Start continuous inventory (FFFF = max repeats)
    UART.write(uart, Protocol.multi_inventory(0xFFFF))

    {:ok, %{uart: uart, buffer: <<>>}}
  end

  # Handle incoming framed messages from circuits_uart
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    case Protocol.parse_frame(data) do
      {:ok, %{type: 0x02, cmd: 0x22, params: params}} ->
        case Protocol.parse_tag(params) do
          {:ok, tag} ->
            GenServer.cast(BibtimeStation.ReadPipeline,
              {:tag_read, %{
                chip_id: tag.epc,
                rssi: tag.rssi,
                read_at: DateTime.utc_now()
              }})
          _ ->
            :ok
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end
end

defmodule BibtimeStation.Reader.Protocol do
  # M100/Invelion protocol — see hardware/R200_PROTOCOL.md
  @header 0xAA
  @end_marker 0xDD
  @type_command 0x00

  def build_frame(cmd, params \\ <<>>) do
    pl = byte_size(params)
    body = <<@type_command, cmd, pl::16-big, params::binary>>
    cs = checksum(body)
    <<@header, body::binary, cs, @end_marker>>
  end

  def set_region(:eu), do: build_frame(0x07, <<0x02>>)
  def set_region(:us), do: build_frame(0x07, <<0x01>>)
  def set_power(cdbm), do: build_frame(0xB6, <<cdbm::16-big>>)
  def single_inventory, do: build_frame(0x22)
  def multi_inventory(count), do: build_frame(0x27, <<0x22, count::16-big>>)
  def stop_inventory, do: build_frame(0x28)

  def parse_tag(<<rssi, pc::16, rest::binary>>) do
    epc_words = (pc >>> 11) &&& 0x1F
    epc_bytes = epc_words * 2
    case rest do
      <<epc::binary-size(epc_bytes), _crc::binary-size(2), _rest::binary>> ->
        {:ok, %{rssi: rssi, pc: pc, epc: Base.encode16(epc)}}
      _ ->
        :error
    end
  end

  defp checksum(body) do
    body |> :binary.bin_to_list() |> Enum.sum() |> rem(256)
  end
end
```

**Note on framing:** The `circuits_uart` library supports a custom framer behavior. We'll implement a `Framer` module that recognizes the `AA...DD` envelope and emits one frame per message. This is cleaner than buffering bytes manually in the GenServer.

**CH340 wake quirk:** During initial testing on macOS, the CH340 USB-to-serial chip needed a brief 9600-baud connection before 115200 worked. This may not be needed on Linux/Pi — verify during initial Nerves testing. If needed, add a wake step in `init/1`.

### 4.3 BibtimeStation.ReadPipeline

```elixir
defmodule BibtimeStation.ReadPipeline do
  use GenServer

  # Receives raw tag reads from Reader.
  # Deduplicates (same chip_id within configurable window).
  # Forwards unique reads to Uplink.

  def init(_opts) do
    window = Application.get_env(:bibtime_station, :read_dedup_window_ms)
    {:ok, %{recent: %{}, dedup_window: window}}
  end

  def handle_cast({:tag_read, read}, state) do
    now = System.monotonic_time(:millisecond)
    chip_id = read.chip_id

    case Map.get(state.recent, chip_id) do
      nil ->
        dispatch(read)
        {:noreply, put_recent(state, chip_id, now)}

      last_seen when now - last_seen > state.dedup_window ->
        dispatch(read)
        {:noreply, put_recent(state, chip_id, now)}

      _recent ->
        # Duplicate within window, ignore
        {:noreply, state}
    end
  end

  defp dispatch(read) do
    GenServer.cast(BibtimeStation.Uplink, {:send_read, read})
  end
end
```

### 4.4 BibtimeStation.Uplink

```elixir
defmodule BibtimeStation.Uplink do
  use GenServer

  # Sends reads to BibTime server.
  # On success: done.
  # On failure: writes to Buffer for later retry.
  # Periodically flushes the buffer when the server is reachable.

  def handle_cast({:send_read, read}, state) do
    payload = %{
      chip_id: read.chip_id,
      read_at: read.timestamp,
      rssi: read.rssi,
      read_count: read.read_count
    }

    case post_read(payload) do
      {:ok, response} ->
        log_response(read, response)
        {:noreply, %{state | online: true}}

      {:error, _reason} ->
        BibtimeStation.Buffer.enqueue(payload)
        {:noreply, %{state | online: false}}
    end
  end

  # Called periodically by a :flush_buffer timer
  def handle_info(:flush_buffer, %{online: true} = state) do
    case BibtimeStation.Buffer.drain(50) do
      [] -> :ok
      reads -> post_batch(reads)
    end
    schedule_flush()
    {:noreply, state}
  end
end
```

### 4.5 BibtimeStation.Buffer

```elixir
defmodule BibtimeStation.Buffer do
  use GenServer

  # Persistent offline buffer using DETS (disk-backed ETS).
  # Survives reboots.
  # Writes go to Nerves' writable data partition.

  def enqueue(read) do
    GenServer.call(__MODULE__, {:enqueue, read})
  end

  def drain(count) do
    GenServer.call(__MODULE__, {:drain, count})
  end

  def init(_) do
    {:ok, table} = :dets.open_file(:read_buffer,
      file: ~c"/data/read_buffer.dets",
      type: :set
    )
    {:ok, %{table: table, counter: restore_counter(table)}}
  end
end
```

### 4.6 BibtimeStation.Heartbeat

```elixir
defmodule BibtimeStation.Heartbeat do
  use GenServer

  # Sends periodic status to BibTime server.
  # Includes: firmware version, uptime, total reads, buffer size,
  #           reader connected (bool), last read timestamp.

  def handle_info(:heartbeat, state) do
    payload = %{
      firmware_version: Application.spec(:bibtime_station, :vsn) |> to_string(),
      uptime_seconds: :erlang.statistics(:wall_clock) |> elem(0) |> div(1000),
      reads_total: BibtimeStation.ReadPipeline.read_count(),
      buffer_size: BibtimeStation.Buffer.size(),
      reader_connected: Process.alive?(Process.whereis(BibtimeStation.Reader)),
    }

    put_heartbeat(payload)
    schedule_heartbeat()
    {:noreply, state}
  end
end
```

---

## Phase 5: Station Monitoring Dashboard

LiveView page in BibTime for race-day monitoring of all connected stations.

### Route

```
/admin/races/:id/stations
```

### Features

- **Station cards** showing: name, assigned split, status dot (green/yellow/red), last heartbeat age, total reads, buffer size
- **Live updates** via PubSub — when a heartbeat or read comes in, the UI updates without polling
- **Station setup flow:** create station → assign to split → shows token + provisioning instructions
- **Alert banner** if any station hasn't sent a heartbeat in >30 seconds
- **Recent reads** per station (last 10, showing bib number + timestamp)

### PubSub integration

When a chip read is ingested:
```elixir
# In Timing.ingest_chip_read/2, after recording:
Phoenix.PubSub.broadcast(Bibtime.PubSub, "race:stations:#{race_id}",
  {:station_read, station_id, %{chip_id: chip_id, bib: participant.bib_number}})
```

When a heartbeat arrives:
```elixir
Phoenix.PubSub.broadcast(Bibtime.PubSub, "race:stations:#{race_id}",
  {:station_heartbeat, station_id, metadata})
```

---

## Implementation Order

### Step 1 — Protocol discovery (Phase 1)

Connect the R200 to a laptop, figure out the serial protocol, write notes. This unblocks all firmware work and might change some assumptions.

### Step 2 — Server API + Station schema (Phase 2)

Build the BibTime server side first. This can be tested with `curl` or a simple Elixir script before any Nerves code exists:

```bash
# Simulate a station read
curl -X POST http://localhost:4000/api/stations/abc123/reads \
  -H "Content-Type: application/json" \
  -d '{"chip_id": "E2003412", "read_at": "2026-06-15T09:23:45.123Z", "rssi": -45}'
```

Deliverables:
- [ ] TimingStation migration + schema
- [ ] `ingest_chip_read/2` function
- [ ] API controller with `/reads`, `/reads/batch`, `/heartbeat` endpoints
- [ ] Station management LiveView (create, list, show token)
- [ ] Tests for ingestion (recorded, duplicate, unmatched)

### Step 3 — Nerves skeleton (Phase 3)

Create the project, get it booting on the Pi, connecting to WiFi, and reachable via SSH. No R200 code yet.

Deliverables:
- [ ] `mix nerves.new bibtime_station`
- [ ] Configure for `rpi0_2`, WiFi, SSH, NTP
- [ ] Burn firmware, verify Pi boots and connects to WiFi
- [ ] Verify `ssh` access and IEx shell on device

### Step 4 — Serial reader (Phase 4.2)

Implement the R200 serial protocol in the Reader GenServer. Test tag reads on the Pi.

Deliverables:
- [ ] `BibtimeStation.Reader` GenServer with `circuits_uart`
- [ ] R200 protocol module (frame parsing, command building)
- [ ] Verify tag reads in IEx on the Pi

### Step 5 — Full pipeline (Phase 4)

Wire up ReadPipeline → Uplink → Buffer → Heartbeat. Connect to the BibTime server. End-to-end test: wave a tag, see a split time appear in the admin UI.

Deliverables:
- [ ] All GenServers from Phase 4
- [ ] End-to-end: tag read → API → split_time → LiveView update
- [ ] Offline buffering: disconnect WiFi, read tags, reconnect, verify buffer flushes

### Step 6 — Monitoring dashboard (Phase 5)

Build the station monitoring LiveView.

Deliverables:
- [ ] Station status cards with live PubSub updates
- [ ] Disconnect alerts
- [ ] Per-station recent reads

---

## Open Questions

1. **R200 serial protocol:** Mercury API or Invelion proprietary? Determines the entire Reader module implementation. Resolved in Phase 1.

2. **Time synchronization:** The Pi's clock is set via NTP on boot. For elapsed time accuracy, we're recording `absolute_time` (UTC) and the server computes `elapsed_ms` from the race start. This means the Pi's clock needs to be reasonably accurate (~100ms). NTP over WiFi typically achieves <50ms accuracy, which is fine for our purposes. If tighter accuracy is needed later, we could use GPS PPS — but that's over-engineering for now.

3. **Multi-split stations:** Currently the plan is one station = one split. If a single station needs to cover multiple splits (e.g., athletes pass the same point twice in a loop course), we'd need split disambiguation logic. Defer this — one station per split is fine for triathlon.

4. **Tag format:** UHF Gen2 tags have a 96-bit EPC (Electronic Product Code). This is the `chip_id` that gets stored on the Participant during check-in and matched during reads. We'll store it as a hex string (e.g., `"E2003412B70C0140"`).

5. **Check-in flow integration:** The existing check-in LiveView already handles associating a `chip_id` with a participant. We might want to also support check-in via the RFID station (wave tag near antenna, type bib number) — but that's a nice-to-have after the core timing flow works.
