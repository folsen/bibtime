# Architecture

BibTime is a self-hosted race timing platform. Elixir/Phoenix 1.8, LiveView, SQLite (ecto_sqlite3), Tailwind v4. Deployed as a single binary with an embedded DB.

The system has two deployable components:

1. **BibTime server** (this repo's top-level `lib/`) — the Phoenix app. Handles registration, results, admin UI, chip-read ingestion.
2. **BibTime station** (`bibtime_station/`) — a standalone Elixir OTP application that runs on a Raspberry Pi next to an R200 RFID reader and POSTs chip reads to the server over HTTP.

## Server Supervision Tree

```
Bibtime.Application
  ├── BibtimeWeb.Telemetry
  ├── Bibtime.Repo (SQLite, WAL mode)
  ├── Ecto.Migrator (auto-runs in releases)
  ├── DNSCluster
  ├── Phoenix.PubSub (name: Bibtime.PubSub)
  ├── Task.Supervisor (name: Bibtime.TaskSupervisor)
  ├── Bibtime.RateLimiter (ETS-based token bucket)
  └── BibtimeWeb.Endpoint (Bandit HTTP server)
```

ChromicPDF is **not** part of the supervision tree — it's lazy-started on
the first PDF export by `Bibtime.Results.Export.ensure_chromic_pdf_started/0`,
which keeps test/dev startup fast and avoids spawning headless Chrome on
servers that never render PDFs.

## Data Model

```
User (accounts)
  ├── role: user | timer | admin
  ├── email, hashed_password (bcrypt)
  └── preferred_locale

Race
  ├── slug (URL identifier), status (draft → registration_open → registration_closed → in_progress → finished → archived)
  ├── race_type: triathlon | running | cycling | swimming | custom
  ├── participant_limit (optional cap on registrations)
  ├── payment fields: payment_required, entry_fee_cents, currency, early_bird_fee_cents, early_bird_deadline
  ├── has_many → RaceCategory (manual categories: name, distance_label, gender filter, age range)
  ├── has_many → RaceAutoCategory (auto-assigned: type=gender|age_group, filter criteria)
  ├── has_many → Split (timing segments: name, short_name, leg_type=swim|bike|run|transition|other, distance_meters, pace_display, sort_order)
  ├── has_many → Participant
  └── has_many → RaceStart (started_at, optional wave_name, optional race_category link)

Participant
  ├── bib_number, first_name, last_name, email, birth_date, gender, club, chip_id
  ├── status: pending_payment | registered | checked_in | racing | dns | dnf | dsq | finished
  ├── checked_in_at, confirmation_token
  ├── belongs_to → Race, RaceCategory, User
  ├── has_many → SplitTime
  └── has_many → Payment

SplitTime
  ├── elapsed_ms (milliseconds from race start), absolute_time
  ├── source: chip | manual | import | adjustment
  ├── raw_chip_data (JSON blob of the raw station payload for chip reads)
  ├── belongs_to → Participant, Split
  └── unique_constraint on [participant_id, split_id]

TimingStation                            (app-level, not scoped to one race)
  ├── name, token (auth, unique)
  ├── status: offline | online | reading | error
  ├── last_seen_at, firmware_version
  ├── metadata (reads_total, uptime_seconds, reader_connected, error_reason, …)
  └── belongs_to → Split (assigned_split, nilify_on_delete, unique when set)

Payment
  ├── Stripe Checkout integration
  ├── stripe_session_id, stripe_payment_intent_id
  ├── amount_cents, currency, status
  └── belongs_to → Participant

RacePhoto
  ├── S3/local storage via Photos.Storage
  ├── bib_numbers (list — tags photos to participants)
  └── belongs_to → Race
```

## Contexts (lib/bibtime/)

| Module | Role | Key Details |
|--------|------|-------------|
| `Accounts` | User CRUD, auth, roles | bcrypt, magic-link login (token-based), phx.gen.auth |
| `Races` | Race CRUD, categories, splits | `Templates` module provides race type presets; `AutoCategorizer` assigns auto-categories to participants based on gender/age |
| `Participants` | Participant CRUD, bib assignment, check-in, chip lookup | `next_bib_number/1` for auto-assignment, `get_participant_by_chip/2` for station reads, `CsvImport` for bulk registration |
| `Timing` | Split times, race starts, timing stations, chip-read ingestion | See dedicated section below |
| `Results` | Result computation + ranking | Delegates to `Calculator` (builds `ParticipantResult` structs with leg_times, total_ms, splits_completed) then `Ranker` (sorts by splits_completed desc, total_ms asc); `Export` for CSV; `PdfTemplate` + ChromicPDF for PDF |
| `Registration` | Public registration flow | Auto-creates user accounts, assigns bibs, sends confirmation emails via `RegistrationNotifier` |
| `Payments` | Stripe Checkout integration | `create_checkout_session/4`, webhook handling, early-bird pricing logic |
| `Photos` | Race photo management | S3 upload via `ExAws.S3`, bib-number tagging |
| `SiteSettings` | Whitelabel singleton (site name, hero copy, CTA, default locale, organizer contact) | Single-row table cached in `:persistent_term`, refreshed on update; assigned to every browser request by `BibtimeWeb.Plugs.AssignSiteSettings` |
| `AuditLog` | Action logging | Tracks admin actions with actor, action, metadata |

### Timing context (`lib/bibtime/timing.ex`)

This is the heart of the real-time side. It owns three concerns:

- **SplitTime** — `record_split_time/1`, `delete_split_time/1`, queries. Every insert/delete broadcasts on `"race:timing:#{race_id}"` and re-derives the participant status (`:registered` → `:racing` → `:finished`, triggered by having a split time for the final-by-sort-order split). Manual overrides (`dns`, `dnf`, `dsq`) are never overwritten.
- **RaceStart** — `start_race/1`, `get_race_start/1`, `list_race_starts/1`. A race can have multiple starts (waves); `get_race_start/1` returns the earliest and is used to compute `elapsed_ms` for chip reads.
- **TimingStation + chip-read ingestion** — see next section.

## Timing Stations

A **timing station** is a physical device (Raspberry Pi + RFID reader) deployed at a split point on the course. Stations are managed centrally, assigned to a `Split` at race time, and POST chip reads to the server. The server is authoritative for participant lookup and split assignment; the station is a "dumb reader" that only knows how to read tags and forward them.

### Hardware

Reference doc: [hardware/HARDWARE_SETUP.md](hardware/HARDWARE_SETUP.md). R200 serial protocol findings in [hardware/R200_PROTOCOL.md](hardware/R200_PROTOCOL.md).

| Component | Detail |
|-----------|--------|
| **Compute** | Raspberry Pi Zero 2 W, Raspberry Pi OS Lite (64-bit) |
| **RFID reader** | Invelion "R200" dev board (actually an M100, firmware V2.3.5) — EU 865-868 MHz, up to 26 dBm output, ~36 reads/sec per tag |
| **Antenna** | 9.2 dBi circular-polarised UHF (860-960 MHz) |
| **Host link** | USB serial (`/dev/ttyUSB0`) via CH340. UART on GPIO (`/dev/serial0`) documented as fallback but not used in the current deployment |
| **Power** | Dual-output USB power bank (10,000-20,000 mAh). Pi draws ~500 mA, R200 ~300 mA peak |
| **Network** | 2.4 GHz WiFi. Optional 4G modem via USB (requires a powered USB hub — tested with an Acer ODK350 5-in-1 USB 3.0 hub) |
| **Shutdown button** | Momentary switch on GPIO3/GND, wired via the `gpio-shutdown` device tree overlay — no software needed |

> **Nerves was abandoned.** An earlier plan (`hardware/NERVES_PLAN.md`) put the station on Nerves firmware, but the stock `nerves_system_rpi0_2` kernel is missing CH340 and CDC-ECM drivers. Pi OS + a regular Elixir release runs the same OTP app and supports the USB peripherals out of the box. The Nerves plan doc is kept for historical context only.

### Station OTP app (`bibtime_station/`)

Standalone Elixir project, separate `mix.exs`. Deployed as a mix release under systemd on the Pi. Deps: `circuits_uart`, `req`, `jason`. No Phoenix, no Ecto — the only persistence is a DETS file for the offline read buffer.

```
BibtimeStation.Supervisor  (strategy: :rest_for_one)
  ├── Buffer         DETS (prod) / ETS (dev/test) — survives restarts
  ├── Reader         owns /dev/ttyUSB0, runs continuous inventory, emits {:tag_read, %{chip_id, rssi, read_at}}
  ├── ReadPipeline   deduplicates same chip_id within dedup window (default 5s), counts reads
  ├── Uplink         POSTs to /api/stations/:token/reads; on failure, enqueues to Buffer; every 5s drains up to 50 queued reads to /reads/batch
  └── Heartbeat      PUTs to /api/stations/:token/heartbeat every 10s with firmware version, uptime, reads_total, buffer_size, reader_connected
```

`rest_for_one` means a Reader crash restarts the whole downstream chain; a Buffer crash restarts everything. The supervision tree only boots in `prod` (or when a test/dev session opts in via `start_supervision_tree: true`) so `iex -S mix` doesn't grab the serial port.

**Reader specifics** (`bibtime_station/lib/bibtime_station/reader.ex`):

- Custom framer (`BibtimeStation.Reader.Framer`) recognises the `AA … DD` envelope — this board does *not* use the standard `BB`/`7E` framing.
- On open: sets region to EU (cmd `0x07`, value `0x02`), sets TX power (cmd `0xB6`, default 20 dBm = `0x07D0` centidBm), starts continuous inventory (cmd `0x27`, repeats `0xFFFF`).
- DTR and RTS must be forced off or the M100 misbehaves.
- CH340 "wake" quirk: on macOS hosts a brief 9600-baud connect is required before 115200 works; detected at runtime via `:os.type/0` so the same release works on dev (Mac) and prod (Pi).
- Inventory watchdog: if no UART data arrives for 5 s the Reader restarts the inventory loop (the reader normally emits `0x15` "no tag found" frames at ~70/s, so silence is a reliable fault signal).
- Port-open failures and UART errors don't crash the process — they log, mark `reader_connected: false` (surfaced in heartbeats and the monitoring UI), and retry on a timer.

**Configuration** via env vars consumed by `bibtime_station/config/runtime.exs`:

| Variable | Purpose |
|----------|---------|
| `BIBTIME_URL` | Server base URL, e.g. `http://192.168.1.231:4000` |
| `STATION_TOKEN` | Per-station auth token (generated in the admin UI) |
| `READER_DEVICE` | Serial port path, default `/dev/ttyUSB0` |
| `BUFFER_PATH` | DETS file location, e.g. `/var/lib/bibtime_station/read_buffer.dets` |

### Station ↔ server communication

Plain HTTP, token auth in the URL. No sockets, no MQTT — simple enough to `curl` during debugging.

```
POST  /api/stations/:token/reads
      {"chip_id": "E2003412B70C0140", "read_at": "2026-06-15T09:23:45.123Z", "rssi": -45}
      → 200 {status: "recorded",  participant_bib: "42", participant_name: "...", elapsed_ms: 1234567}
      → 200 {status: "duplicate", participant_bib: "42"}          same participant × split already recorded
      → 200 {status: "unmatched", chip_id: "..."}                 chip not assigned to any participant
      → 401                                                       bad token

POST  /api/stations/:token/reads/batch
      {"reads": [ {...}, {...}, ... ]}   used by Uplink to flush the offline buffer
      → 200 {results: [ ...one per read... ]}

PUT   /api/stations/:token/heartbeat
      {"firmware_version": "0.1.0", "reads_total": 847, "uptime_seconds": 14400,
       "buffer_size": 0, "reader_connected": true, "error_reason": null}
      → 200 {status: "ok"}
```

Auth is handled by `BibtimeWeb.API.StationAuth` — looks up the station by token, assigns it to `conn.assigns.station`, halts with 401 otherwise. There is no user session and no CSRF for this API.

### Chip-read ingestion (`Timing.ingest_chip_read/2`)

The station sends raw `{chip_id, read_at, rssi}`. The server resolves that into a `SplitTime`:

```
ingest_chip_read(station, raw)
  1. station.assigned_split_id must be set          → {:error, :station_unassigned}
  2. Participants.get_participant_by_chip(race, chip_id)
     - nil                                          → broadcast :unmatched, {:ok, :unmatched}
  3. If participant already has a SplitTime for this split → {:ok, :duplicate, participant}
  4. parse_read_at (ISO8601 → UTC DateTime; nil → now)
  5. get_race_start(race_id)                        → {:error, :race_not_started} if none
  6. elapsed_ms = read_at − race_start.started_at
  7. record_split_time(participant, split, elapsed_ms, absolute_time, source: :chip,
                        raw_chip_data: JSON of raw payload)
     → broadcasts {:split_time_recorded, st} on "race:timing:#{race_id}"
     → broadcasts {:station_read, station_id, payload} on "race:stations:#{race_id}"
     → {:ok, :recorded, participant, split_time}
```

Key invariants:

- The station never knows the `split_id`. The server looks it up from `station.assigned_split_id`. Reassigning a station to a different split on the server takes effect on the next read without touching the station.
- Duplicates are not errors — they're a normal consequence of a participant passing the antenna multiple times or batch-flushing already-delivered reads.
- Unmatched chips are also not errors — they're reported so the monitoring UI can surface rogue tags.

### Station admin + monitoring

| LiveView | Route | Purpose |
|----------|-------|---------|
| `Admin.StationLive.GlobalIndex` | `/admin/stations` (admin only) | Create/manage stations app-wide, show tokens for provisioning |
| `Admin.StationLive.Index` | `/admin/races/:id/stations` (timer/admin) | Per-race split×station assignment grid, live heartbeat/last-seen indicators, surfaces `reader_connected: false` and `error_reason` so field problems are visible from the venue |

Both subscribe to `"race:stations:#{race_id}"` for live updates from heartbeats and reads. A periodic `:tick` recomputes staleness (`last_seen_at > ~20 s` flags a station as stale on the dashboard).

### Check-in flow

`Admin.CheckInLive.Index` (`/admin/races/:id/check-in`, timer/admin role) associates a `chip_id` with a participant and sets `checked_in_at` + `status: :checked_in`. Check-in subscribes to `"race:checkin:#{race_id}"` so multiple check-in stations stay in sync. The participant's chip is what `Participants.get_participant_by_chip/2` matches during chip-read ingestion.

## Real-Time Flow

```
Admin.TimingLive         POST /api/stations/:token/reads       BibtimeStation.Uplink
(manual split entry)              (chip read)                   (from Pi/R200)
        │                              │                              │
        ▼                              ▼                              │
Timing.record_split_time  ◄──── Timing.ingest_chip_read  ◄────────────┘
        │
        ├── DB insert
        ├── update_participant_status (registered → racing → finished)
        └── Phoenix.PubSub broadcast
              "race:timing:#{race_id}"              →  Public.ResultsLive, Public.KioskLive (re-rank + re-render)
              "race:stations:#{race_id}"            →  Admin.StationLive dashboards
```

## Routes & LiveViews

**Public** (no auth):
- `GET /` — landing page (PageController)
- `/races/:slug` — RaceLive.Show
- `/races/:slug/results` — ResultsLive.Index (+ CSV/PDF export via ExportController)
- `/races/:slug/register` — RegistrationLive.New, `.Show` (confirmation), `.MyRegistration`
- `/races/:slug/photos` — PhotoLive.Index
- `/races/:slug/kiosk` — KioskLive.Index (fullscreen layout, no nav — for projectors; shows latest splits)

**Authenticated** (any logged-in user):
- `/profile` — ProfileLive.Index (+ `/profile/races/:participant_id`)
- `/my-races` — MyRacesLive.Index, `.Edit`

**Admin** (require_admin_user):
- `/admin/races` — CRUD, show, participants, photos, payments
- `/admin/users` — user management
- `/admin/stations` — global station management
- `/admin/settings` — whitelabel site settings (SettingsLive.Edit)

**Timer** (require_timer_or_admin_user):
- `/admin/races/:id/timing` — TimingLive.Index (manual split-time recording, file-upload import of timing data)
- `/admin/races/:id/check-in` — CheckInLive.Index (assign chips, mark checked-in)
- `/admin/races/:id/stations` — StationLive.Index (per-race station dashboard)

**API** (token auth, no CSRF):
- `POST /api/stations/:token/reads` — single chip read
- `POST /api/stations/:token/reads/batch` — offline buffer flush
- `PUT  /api/stations/:token/heartbeat` — station status
- `GET  /healthz` — load balancer health check
- `POST /webhooks/stripe` — signature-verified Stripe webhook

**Dev** (mounted only when `:dev_routes` is enabled, behind HTTP basic auth):
- `/dev/emails` — `Dev.EmailPreviewLive` (rendered email previews)
- `/dev/dashboard` — Phoenix LiveDashboard
- `/dev/mailbox` — Swoosh local mailbox preview

## Layouts

- `app` — public pages (nav bar, standard chrome)
- `admin` — sidebar navigation
- `kiosk` / `kiosk_root` — fullscreen, no nav (venue displays)

## Frontend

- Tailwind CSS v4 (configured in `assets/css/app.css`, no tailwind.config.js)
- esbuild bundles `assets/js/app.js`
- JS files: `app.js`, `theme.js`, `kiosk-theme.js`
- Fonts: DM Sans (body), DM Mono (timing data)
- Heroicons via `<.icon name="hero-x-mark" />` component
- Component modules: `CoreComponents`, `Layouts`, `RaceComponents`

## Auth Model

- `Scope` struct (`%Scope{user: user}`) threaded through LiveViews via `on_mount`
- Access `@current_scope.user` in templates (not `@current_user`)
- Roles: `user` (default), `timer` (timing/check-in/station UIs), `admin` (full access)
- Magic-link login: email → token URL → session (no password entry in browser)
- Station API auth is separate: per-station token in the URL, no user session

## i18n

- Gettext-based, locales: `en` (default), `sv`
- `BibtimeWeb.LocaleHelpers` for status labels, date formatting, select options
- `SetLocale` plug reads locale from session/params
- PO files in `priv/gettext/sv/LC_MESSAGES/`

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `phoenix` 1.8, `phoenix_live_view` 1.1 | Web framework + real-time UI |
| `ecto_sqlite3` | SQLite adapter |
| `bcrypt_elixir` | Password hashing |
| `req` | HTTP client (use this, not HTTPoison/Tesla) |
| `swoosh` | Email delivery |
| `stripity_stripe` | Stripe API |
| `ex_aws` + `ex_aws_s3` | S3 photo storage |
| `chromic_pdf` | PDF generation (headless Chrome, lazy-started) |
| `gettext` | i18n |
| `heroicons` | Icon set |

Station-side (`bibtime_station/mix.exs`): `circuits_uart`, `req`, `jason`. Elixir 1.17+.

## File Layout

```
lib/
  bibtime/                    # Business logic (contexts)
    accounts/                 # User, UserToken, UserNotifier, Scope
    races/                    # Race, RaceCategory, RaceAutoCategory, Split, Templates, AutoCategorizer
    participants/             # Participant, CsvImport
    timing/                   # SplitTime, RaceStart, TimingStation, CsvImport
    results/                  # Calculator, Ranker, ParticipantResult, Export, PdfTemplate
    registration/             # RegistrationNotifier
    payments/                 # Payment, PaymentNotifier
    photos/                   # RacePhoto, Storage
    site_settings/            # SiteSettings (whitelabel singleton schema)
    audit_log/                # AuditLogEntry
    mailer/                   # Swoosh email previews (used by Dev.EmailPreviewLive)
    application.ex            # OTP supervisor
    mailer.ex                 # Swoosh.Mailer
    rate_limiter.ex           # ETS-based token bucket GenServer
    release.ex                # Release tasks (migrate, rollback) for `bin/bibtime eval`
  bibtime_web/                # Web layer
    live/
      admin/                  # RaceLive, ParticipantLive, TimingLive, CheckInLive, StationLive, UserLive, PhotoLive, PaymentLive, SettingsLive
      public/                 # RaceLive, ResultsLive, KioskLive, RegistrationLive, ProfileLive, MyRacesLive, PhotoLive
      dev/                    # EmailPreviewLive (dev-only)
    controllers/
      api/                    # StationController, StationAuth (token plug)
      …                       # PageController, ExportController, HealthController, StripeWebhookController,
                              #   CheckoutController, PhotoController, LocaleController,
                              #   UserSession/UserSettings/UserRegistration controllers
    components/               # CoreComponents, Layouts, RaceComponents (+ layouts/ heex templates)
    helpers/                  # LocaleHelpers
    plugs/                    # SetLocale, RateLimiter, AssignSiteSettings

bibtime_station/              # Standalone Pi-side Elixir release
  lib/bibtime_station/
    application.ex            # rest_for_one supervisor
    buffer.ex                 # DETS/ETS offline read buffer
    reader.ex                 # R200 serial GenServer
    reader/                   # Framer, Protocol (AA…DD frame encoding)
    read_pipeline.ex          # dedup + read counter
    uplink.ex                 # POSTs reads, drains buffer
    heartbeat.ex              # periodic PUT to /heartbeat
  config/                     # dev, prod, runtime, test configs
  deploy/                     # systemd unit, /etc/default defaults
  DEPLOYMENT.md               # Pi provisioning walkthrough

hardware/
  HARDWARE_SETUP.md           # physical assembly + Pi OS setup
  R200_PROTOCOL.md            # reverse-engineered serial protocol
  NERVES_PLAN.md              # historical — superseded by the Pi OS deployment
  IMG_*.jpeg / *.heic         # reference photos of the current test rig

test/
  bibtime/                    # Context tests
  bibtime_web/                # Controller + LiveView tests
  support/                    # Test helpers, fixtures, conn_case, data_case
```
