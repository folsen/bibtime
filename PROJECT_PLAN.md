# BibTime — Self-Hosted Race Timing Platform

## Vision

An open-source, self-hosted race timing application built with Elixir and Phoenix. Designed for race organizers who want full control over their timing infrastructure — no SaaS fees, no vendor lock-in, just a clean tool you run yourself.

The first target race type is **triathlon**, with multi-split timing (swim, T1, bike, T2, run) and timing chip integration.


## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Elixir | Concurrency, fault tolerance, real-time via OTP |
| Web framework | Phoenix 1.8+ | LiveView for real-time results, HEEx templates |
| Database | SQLite via Ecto + `ecto_sqlite3` | Zero-ops for self-hosting, single-file DB, easy backups |
| Real-time | Phoenix LiveView + PubSub | Live results updates without writing JavaScript |
| Frontend | LiveView + Tailwind CSS | Server-rendered, minimal JS, responsive |
| Auth | `mix phx.gen.auth` | Built-in Phoenix auth generator, simple and solid |
| Deployment | Single binary via `mix release` | Easy to self-host, minimal dependencies |
| Timing chip I/O | GenServer-based decoder | Pluggable protocol adapters for different chip systems |


## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Phoenix App                          │
│                                                         │
│  ┌──────────┐  ┌──────────────┐  ┌───────────────────┐ │
│  │  LiveView │  │  Admin Panel │  │  Public Results   │ │
│  │  (Real-   │  │  (Race CRUD, │  │  (Archive,        │ │
│  │   time)   │  │   Timing)    │  │   Search)         │ │
│  └─────┬─────┘  └──────┬───────┘  └────────┬──────────┘ │
│        │               │                    │            │
│  ┌─────┴───────────────┴────────────────────┴──────────┐│
│  │                  Context Layer                       ││
│  │  Races | Participants | Timing | Registration       ││
│  └─────────────────────┬───────────────────────────────┘│
│                        │                                 │
│  ┌─────────────────────┴───────────────────────────────┐│
│  │              Ecto + SQLite                           ││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │           Timing Subsystem (OTP)                    ││
│  │  ┌────────────┐  ┌──────────┐  ┌────────────────┐  ││
│  │  │ ChipReader │  │ Manual   │  │ CSV/File       │  ││
│  │  │ GenServer  │  │ Entry    │  │ Import         │  ││
│  │  └─────┬──────┘  └────┬─────┘  └───────┬────────┘  ││
│  │        └──────────────┴────────────────┘            ││
│  │                    │                                 ││
│  │           PubSub (broadcast splits)                 ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```


## Data Model

### Core Entities

**Race**
The top-level event (e.g., "Stadsparken Triathlon 2026").

```
races
├── id (primary key)
├── name (string)
├── slug (string, unique, for URLs)
├── description (text)
├── date (date)
├── location (string)
├── race_type (enum: triathlon, running, cycling, swimming, custom)
├── status (enum: draft, registration_open, registration_closed, in_progress, finished, archived)
├── config (json — flexible race-specific settings)
├── inserted_at / updated_at
```

**RaceCategory**
Divisions within a race (e.g., "Elite Men", "Age Group 40-44", "Sprint Distance").

```
race_categories
├── id
├── race_id (FK → races)
├── name (string)
├── distance_label (string, e.g., "Olympic", "Sprint")
├── gender (enum: any, male, female)
├── min_age / max_age (integer, nullable)
├── sort_order (integer)
```

**Split**
Defines the timing points for a race. For a triathlon: swim_finish, t1_out, bike_finish, t2_out, run_finish.

```
splits
├── id
├── race_id (FK → races)
├── name (string, e.g., "Swim Finish")
├── short_name (string, e.g., "SWIM")
├── leg_type (enum: swim, bike, run, transition, other)
├── distance_meters (integer, nullable)
├── sort_order (integer)
```

**Participant**
A registered person in a race.

```
participants
├── id
├── race_id (FK → races)
├── race_category_id (FK → race_categories)
├── bib_number (string, unique per race)
├── first_name (string)
├── last_name (string)
├── email (string)
├── birth_date (date)
├── gender (enum: male, female, other)
├── club (string, nullable)
├── chip_id (string, nullable — timing chip identifier)
├── status (enum: registered, dns, dnf, dsq, finished)
├── registration_data (json — flexible extra fields)
├── inserted_at / updated_at
```

**SplitTime**
A recorded time at a split point for a participant. This is the heart of the timing system.

```
split_times
├── id
├── participant_id (FK → participants)
├── split_id (FK → splits)
├── absolute_time (utc_datetime_usec — wall-clock time)
├── elapsed_ms (integer — milliseconds from race gun time)
├── source (enum: chip, manual, import, adjustment)
├── raw_chip_data (string, nullable — raw data from chip reader)
├── inserted_at
```

**RaceStart**
Tracks the official start time(s). Supports wave starts.

```
race_starts
├── id
├── race_id (FK → races)
├── race_category_id (FK → race_categories, nullable — null means all)
├── started_at (utc_datetime_usec)
├── wave_name (string, nullable)
```

**User**
Admin user(s) for the self-hosted instance.

```
users
├── id
├── email (string)
├── hashed_password (string)
├── inserted_at / updated_at
```

### Key Queries the Model Supports

- **Live results**: Join participants → split_times → splits, ordered by latest split completed, then elapsed time.
- **Category results**: Filter by race_category_id, rank by finish split elapsed_ms.
- **Split-by-split breakdown**: For each participant, show all split times as columns (swim, T1, bike, T2, run, total).
- **DNS/DNF/DSQ tracking**: Participant status field handles non-finishers.
- **Chip lookup**: When a chip fires, look up participant by chip_id, determine which split based on reader location, record split_time.


## Triathlon-Specific Design

A triathlon race would be configured with these splits (in order):

| # | Split | Leg Type | Notes |
|---|---|---|---|
| 1 | Swim Finish | swim | Chip mat at swim exit |
| 2 | T1 Out | transition | Chip mat leaving transition |
| 3 | Bike Finish | bike | Chip mat at bike dismount |
| 4 | T2 Out | transition | Chip mat leaving T2 |
| 5 | Run Finish | run | Chip mat at finish line |

Derived times (calculated, not stored):
- Swim time = Split 1 elapsed - start time
- T1 time = Split 2 - Split 1
- Bike time = Split 3 - Split 2
- T2 time = Split 4 - Split 3
- Run time = Split 5 - Split 4
- Total time = Split 5 elapsed - start time


## Timing Chip Integration (Research Area)

### Overview

Timing chips (RFID transponders) are read by antenna mats or readers placed at split points. The reader sends timestamped chip reads to a connected system.

### Common Systems to Research

| System | Protocol | Notes |
|---|---|---|
| **MYLAPS** | Proprietary TCP/IP stream | Industry standard, expensive. Decoders send real-time data. |
| **Race Result** | TCP/IP + HTTP API | Modern system, well-documented API. Active decoder pushes reads. |
| **Impinj / LLRP** | LLRP (Low Level Reader Protocol) | Open RFID standard. Used with UHF RFID chips. |
| **J-Chip** | Serial / TCP | Older but still widely used in Nordics. |
| **RFID Direct / DIY** | Serial / USB | Low-cost UHF readers, various Chinese manufacturers. |

### Architecture for Chip Integration

```elixir
# Pluggable adapter pattern
defmodule BibTime.Timing.Adapter do
  @callback connect(config :: map()) :: {:ok, pid()} | {:error, term()}
  @callback decode_read(raw_data :: binary()) :: {:ok, ChipRead.t()} | {:error, term()}
end

# Each chip system gets its own adapter
defmodule BibTime.Timing.Adapters.RaceResult do
  @behaviour BibTime.Timing.Adapter
  # ...
end

defmodule BibTime.Timing.Adapters.LLRP do
  @behaviour BibTime.Timing.Adapter
  # ...
end
```

Each adapter runs as a GenServer that:
1. Connects to the chip reader (TCP/serial/USB)
2. Decodes incoming reads into a standard `%ChipRead{}` struct
3. Publishes reads to Phoenix.PubSub
4. The timing engine matches chip IDs to participants and records split times

### Phase 1 Approach

Start with **manual time entry** and **CSV import** as the primary timing methods. This lets you build and validate the entire results pipeline without needing physical chip hardware. Add chip reader adapters incrementally.


## Feature Roadmap

### Phase 1 — Foundation (MVP)

Core infrastructure and a working triathlon timing system with manual entry.

- Phoenix project setup with SQLite, auth, Tailwind
- Data model: races, categories, splits, participants, split_times
- Admin: create/edit races, define splits and categories
- Admin: add/manage participants (manual entry)
- Admin: record split times (manual entry with clock)
- Admin: import split times from CSV
- Public: live results page (LiveView, auto-updating)
- Public: results table with split-by-split breakdown
- Public: category filtering and overall rankings

### Phase 2 — Registration & Polish

- Public registration form (configurable fields per race)
- Email confirmation for registrations
- Participant self-service (view own results, update info)
- Results export (CSV, PDF)
- Race page with info, start lists, and results
- Improved live results: auto-scroll, highlight recent finishers
- Mobile-friendly timing entry interface for race day

### Phase 3 — Timing Chip Integration

- Adapter framework for chip readers
- First adapter (likely LLRP/UHF or Race Result, depending on hardware)
- Real-time chip read → split time pipeline
- Chip assignment management (assign chips to bibs)
- Duplicate read filtering and error handling
- Manual override/correction tools for bad reads

### Phase 4 — Advanced Features

- Multi-race archive with search across all events
- Participant profiles (results history across races)
- Race templates (pre-configured split setups for common race types)
- Webhooks / API for external integrations
- Kiosk mode (big-screen display for race venue)
- SMS/push notifications for split times (supporters tracking athletes)
- Photo integration (link finish photos to bib numbers)


## Project Structure

```
bibtime/
├── lib/
│   ├── bibtime/
│   │   ├── accounts/          # User auth (phx.gen.auth)
│   │   │   ├── user.ex
│   │   │   └── ...
│   │   ├── races/             # Race management context
│   │   │   ├── race.ex
│   │   │   ├── race_category.ex
│   │   │   └── split.ex
│   │   ├── participants/      # Participant context
│   │   │   └── participant.ex
│   │   ├── timing/            # Timing engine context
│   │   │   ├── split_time.ex
│   │   │   ├── race_start.ex
│   │   │   ├── engine.ex      # Core timing logic
│   │   │   └── adapters/      # Chip reader adapters
│   │   │       ├── adapter.ex # Behaviour definition
│   │   │       ├── manual.ex
│   │   │       └── csv_import.ex
│   │   ├── registration/      # Registration context (Phase 2)
│   │   │   └── ...
│   │   └── results/           # Results computation & ranking
│   │       ├── calculator.ex  # Split time calculations
│   │       └── ranker.ex      # Ranking logic
│   ├── bibtime_web/
│   │   ├── live/
│   │   │   ├── admin/         # Admin LiveViews
│   │   │   │   ├── race_live/
│   │   │   │   ├── participant_live/
│   │   │   │   └── timing_live/
│   │   │   └── public/        # Public LiveViews
│   │   │       ├── results_live.ex
│   │   │       └── race_live.ex
│   │   ├── controllers/       # Traditional controllers (downloads, etc.)
│   │   ├── components/        # Shared UI components
│   │   └── router.ex
├── priv/
│   └── repo/
│       └── migrations/
├── test/
├── config/
├── mix.exs
└── README.md
```


## Key Design Decisions

### Why SQLite?

For a self-hosted app targeting small local races, SQLite is the perfect fit. It eliminates the need to install and manage PostgreSQL, the entire database is a single file that's trivially backed up, and for the concurrency levels of a local race (hundreds of participants, single admin), SQLite with WAL mode handles the load easily. The `ecto_sqlite3` adapter is mature and well-maintained.

If someone later needs PostgreSQL (e.g., running a larger operation), the Ecto abstraction makes migration straightforward.

### Why LiveView for Real-time Results?

LiveView eliminates the need to build a separate JavaScript frontend or manage WebSocket connections manually. When a split time is recorded, the timing engine broadcasts via PubSub, and every connected LiveView showing results updates instantly. This is exactly the use case LiveView was built for.

### Self-Hosting Model

The app should be deployable as:
1. A Mix release (single binary + runtime)
2. A Docker container (for those who prefer it)
3. Potentially a Fly.io / Railway one-click deploy

Configuration via environment variables and a simple `config.exs` override file.


## Getting Started (Next Steps)

```bash
# 1. Create the Phoenix project
mix phx.new bibtime --database sqlite3

# 2. Set up auth
mix phx.gen.auth Accounts User users

# 3. Create initial migrations for the data model

# 4. Build out contexts: Races, Participants, Timing, Results

# 5. Build admin LiveViews for race management

# 6. Build public results LiveView

# 7. Build timing entry interface
```


## Open Questions

1. **Timing chip hardware**: Which system to target first? Need to research what's available and affordable for small race organizers in Sweden/Nordics.
2. **Payment integration**: For registration fees — Stripe? Swish? Or keep it out of scope and let organizers handle payment separately?
3. **Internationalization**: Start with English + Swedish, or English-only first?
4. **License**: MIT? AGPLv3? Apache 2.0?
