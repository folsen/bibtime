# Architecture

BibTime is a self-hosted race timing platform. Elixir/Phoenix 1.8, LiveView, SQLite (ecto_sqlite3), Tailwind v4. Deployed as a single binary with embedded DB.

## Supervision Tree

```
Bibtime.Application
  ├── BibtimeWeb.Telemetry
  ├── Bibtime.Repo (SQLite, WAL mode)
  ├── Ecto.Migrator (auto-runs in releases)
  ├── DNSCluster
  ├── Phoenix.PubSub (name: Bibtime.PubSub)
  ├── Bibtime.RateLimiter (ETS-based token bucket)
  ├── ChromicPDF (headless Chrome for PDF export)
  └── BibtimeWeb.Endpoint (Bandit HTTP server)
```

## Data Model

```
User (accounts)
  ├── role: user | timer | admin
  ├── email, hashed_password (bcrypt)
  └── preferred_locale

Race
  ├── slug (URL identifier), status (draft → registration_open → registration_closed → in_progress → finished → archived)
  ├── race_type: triathlon | running | cycling | swimming | custom
  ├── payment fields: payment_required, entry_fee_cents, currency, early_bird_fee_cents, early_bird_deadline
  ├── has_many → RaceCategory (manual categories: name, distance_label, gender filter, age range)
  ├── has_many → RaceAutoCategory (auto-assigned: type=gender|age_group, filter criteria)
  ├── has_many → Split (timing segments: name, short_name, leg_type=swim|bike|run|transition|other, distance_meters, pace_display, sort_order)
  ├── has_many → Participant
  └── has_many → RaceStart (started_at, optional wave_name, optional race_category link)

Participant
  ├── bib_number, first_name, last_name, email, birth_date, gender, club, chip_id
  ├── status: pending_payment | registered | racing | dns | dnf | dsq | finished
  ├── confirmation_token (for registration flow)
  ├── belongs_to → Race, RaceCategory, User
  ├── has_many → SplitTime
  └── has_many → Payment

SplitTime
  ├── elapsed_ms (milliseconds from race start), absolute_time
  ├── source: chip | manual | import | adjustment
  ├── belongs_to → Participant, Split
  └── unique_constraint on [participant_id, split_id]

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
| `Participants` | Participant CRUD, bib assignment | `next_bib_number/1` for auto-assignment, `list_participants/1` preloads `race_category` |
| `Timing` | Split time recording, race starts | Broadcasts `{:split_time_recorded, st}` and `{:split_time_deleted, st}` on `"race:timing:#{race_id}"` via PubSub; `CsvImport` for bulk import |
| `Results` | Result computation + ranking | Delegates to `Calculator` (builds `ParticipantResult` structs with leg_times, total_ms, splits_completed) then `Ranker` (sorts by splits_completed desc, total_ms asc); `Export` for CSV; `PdfTemplate` + ChromicPDF for PDF |
| `Registration` | Public registration flow | Auto-creates user accounts, assigns bibs, sends confirmation emails via `RegistrationNotifier` |
| `Payments` | Stripe Checkout integration | `create_checkout_session/4`, webhook handling, early-bird pricing logic |
| `Photos` | Race photo management | S3 upload via `ExAws.S3`, bib-number tagging |
| `AuditLog` | Action logging | Tracks admin actions with actor, action, metadata |

## Real-Time Flow

```
Admin.TimingLive (records split time)
  → Timing.record_split_time/1
    → DB insert
    → PubSub broadcast on "race:timing:#{race_id}"
      → Public.ResultsLive.Index (re-calculates + re-ranks)
      → Public.KioskLive.Index (re-calculates + re-ranks)
```

## Routes & LiveViews

**Public** (no auth):
- `GET /` — landing page (PageController)
- `/races/:slug` — RaceLive.Show
- `/races/:slug/results` — ResultsLive.Index (+ CSV/PDF export via ExportController)
- `/races/:slug/register` — RegistrationLive.New
- `/races/:slug/photos` — PhotoLive.Index
- `/races/:slug/kiosk` — KioskLive.Index (fullscreen layout, no nav — for projectors)

**Authenticated** (any logged-in user):
- `/profile` — ProfileLive.Index
- `/my-races` — MyRacesLive.Index (participant's own results across races)

**Admin** (require_admin_user):
- `/admin/races` — CRUD, show, participants, photos, payments
- `/admin/users` — user management

**Timer** (require_timer_or_admin_user):
- `/admin/races/:id/timing` — TimingLive.Index (split time recording UI)

**API**:
- `GET /healthz` — health check
- `POST /webhooks/stripe` — Stripe webhook (signature-verified)

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
- Roles: `user` (default), `timer` (can access timing UI), `admin` (full access)
- Magic-link login: email → token URL → session (no password entry in browser)

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
| `chromic_pdf` | PDF generation (headless Chrome) |
| `gettext` | i18n |
| `heroicons` | Icon set |

## File Layout

```
lib/
  bibtime/                    # Business logic (contexts)
    accounts/                 # User, UserToken, UserNotifier, Scope
    races/                    # Race, RaceCategory, RaceAutoCategory, Split, Templates, AutoCategorizer
    participants/             # Participant
    timing/                   # SplitTime, RaceStart, CsvImport
    results/                  # Calculator, Ranker, ParticipantResult, Export, PdfTemplate
    registration/             # RegistrationNotifier
    payments/                 # Payment, PaymentNotifier
    photos/                   # RacePhoto, Storage
    audit_log/                # AuditLogEntry
  bibtime_web/                # Web layer
    live/
      admin/                  # RaceLive, ParticipantLive, TimingLive, UserLive, PhotoLive, PaymentLive
      public/                 # RaceLive, ResultsLive, KioskLive, RegistrationLive, ProfileLive, MyRacesLive, PhotoLive
    controllers/              # PageController, ExportController, HealthController, StripeWebhookController, auth controllers
    components/               # CoreComponents, Layouts, RaceComponents
    helpers/                  # LocaleHelpers
    plugs/                    # SetLocale, RateLimiter
test/
  bibtime/                    # Context tests
  bibtime_web/                # Controller + LiveView tests
  support/                    # Test helpers, fixtures, conn_case, data_case
```
