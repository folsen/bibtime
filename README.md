# BibTime

BibTime is a self-hosted race timing platform built with Elixir and Phoenix LiveView. It handles the full lifecycle of endurance events — from race setup and participant registration through live timing to real-time results and photo galleries. Designed for simplicity, it uses SQLite for single-file deployment so you can run it on a single server with zero external database infrastructure.

## Getting Started

### Prerequisites

- Elixir ~> 1.15
- Erlang/OTP (compatible with your Elixir version)
- Node.js (for asset building)
- Chrome/Chromium (for PDF export via ChromicPDF)

### Installation

```bash
# Clone the repository
git clone <repo-url> bibtime
cd bibtime

# Install dependencies, create database, run migrations, seed data, and build assets
mix setup

# Start the development server
mix phx.server
```

The app will be available at [http://localhost:4000](http://localhost:4000).

### Configuration

BibTime uses the standard Phoenix configuration in `config/`. Key things to configure for production:

- **Secret key base** — set `SECRET_KEY_BASE`
- **Host/URL** — configure your domain in `config/runtime.exs`
- **Email (Swoosh)** — configure your mailer adapter for magic link login and confirmation emails
- **Stripe** — set `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` for payment processing
- **S3 storage** (optional) — configure ExAws for cloud photo storage, or use the default local filesystem

### Running Tests

```bash
mix test                     # Run all tests
mix test path/to/test.exs    # Run a single test file
mix test --failed             # Re-run only failed tests
mix precommit                # Full QA: compile (warnings-as-errors), unused deps, format, test
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Elixir |
| Web framework | Phoenix 1.8 + LiveView 1.1 |
| Database | SQLite (via ecto_sqlite3, WAL mode) |
| Frontend | Tailwind CSS v4, Heroicons |
| PDF generation | ChromicPDF |
| Payments | Stripe (via stripity_stripe) |
| File storage | Local filesystem or S3-compatible (via ExAws) |
| Email | Swoosh |
| HTTP client | Req |
| i18n | Gettext (English, Swedish) |

## Features

### Race Management

- **Full race lifecycle** — create, edit, clone, and archive races through statuses: Draft, Registration Open, Registration Closed, In Progress, Finished, Archived
- **Multiple race types** — triathlon, running, cycling, swimming, and custom events
- **Race templates** — 8 built-in templates (Olympic Triathlon, Sprint Triathlon, Duathlon, Aquathlon, 5K, 10K, Half Marathon, Marathon) with preconfigured splits and categories
- **Clone races** — duplicate an existing race as a starting point for a new event
- **Splits/segments** — define multiple legs per race (e.g., Swim, T1, Bike, T2, Run) with leg type, distance, and configurable pace display (min/km, min/mi, sec/100m, or hidden)
- **Manual categories** — create categories like "Elite Men" or "Age Group Women" with gender filters, age ranges, distance labels, and sort order
- **Automatic categories** — auto-categorize participants by gender and/or age group (configurable age ranges, calculated from race date)
- **Per-race configuration** — custom JSON config, default locale, payment settings

### Participant Management

- **Admin participant management** — add, edit, search, sort, paginate, and delete participants
- **Search and filter** — search by name or bib number, sort by bib/name/status
- **Bib assignment** — automatic bib number generation on registration
- **Chip ID tracking** — store electronic timing chip identifiers per participant
- **Status tracking** — Registered, Pending Payment, Racing, Finished, DNS, DNF, DSQ with automatic transitions based on split times
- **Manual status overrides** — mark participants as DNS/DNF/DSQ which prevents automatic status updates
- **Category assignment** — assign participants to manual categories
- **Club/team field** — track participant team affiliation

### Public Registration

- **Self-service registration** — public registration form accessible via race slug URL
- **Conditional form fields** — gender and birth date fields appear based on race auto-category configuration
- **Category selection** — participants choose their category during registration (when applicable)
- **Auto account creation** — user account automatically created from email if it doesn't exist
- **Prefill from history** — form pre-populates with data from the user's most recent race registration
- **Registration status control** — open and close registration independently of race status

### Payment Processing (Stripe)

- **Per-race payment configuration** — entry fee, currency (SEK, EUR, NOK, DKK), early bird pricing with deadline
- **Stripe Checkout integration** — secure hosted payment pages with automatic redirect
- **Webhook handling** — automatic payment confirmation and participant status update on successful payment
- **Payment management** — admin view of all payments with status tracking (pending, completed, refunded)
- **Refund processing** — issue refunds through the admin interface via Stripe API
- **Payment summary** — dashboard cards showing total collected, pending, and refunded amounts
- **Confirmation emails** — automatic email sent after successful payment

### Live Timing

- **Race start recording** — record official start time
- **Manual split time entry** — real-time entry interface for race officials with bib number input and split selection
- **CSV bulk import** — import timing data from electronic timing systems (supports HH:MM:SS.mmm, HH:MM:SS, MM:SS, and raw milliseconds)
- **Import validation** — validates bib numbers, split names, time formats, and duplicate detection with detailed per-row error messages
- **Atomic imports** — all-or-nothing transactions prevent partial data
- **Timing console** — dedicated admin interface with live timer, recent entries, next-up queue, and CSV import
- **Multi-operator support** — multiple timers can work simultaneously via PubSub real-time sync
- **Split time deletion** — remove incorrect times with automatic status recalculation

### Results

- **Automatic calculation** — leg times, total times, and split counts computed from raw split data
- **Ranking algorithm** — ranks by splits completed (descending), then total time (ascending), then bib number; inactive participants (DNS/DNF/DSQ) listed without rank
- **Category rankings** — separate rankings within each manual and auto-category alongside overall standings
- **Real-time updates** — results page updates live as new split times are recorded via PubSub
- **Filtering** — filter by manual category, gender, or age group
- **Sorting** — sort by rank, bib, name, or individual split times
- **Recently finished highlight** — visual indicator for participants who just crossed a split
- **Statistics** — total participants, finished count, podiums, DNS/DNF/DSQ counts

### Results Export

- **CSV export** — full results with rank, bib, name, club, category, gender category, age group, split times, pace per split, total time, and status
- **PDF export** — professional poster-board layout with race header, statistics bar, results table, and accolades section; landscape orientation optimized for printing and display

### Kiosk Mode

- **Fullscreen display** — dedicated layout for TVs and projectors with no navigation chrome
- **Automatic category rotation** — cycles through category leaderboards every 15 seconds
- **URL parameter customization** — control category (`category=overall`), visible columns, scroll speed (`slow|normal|fast`), and theme (`light|dark`)
- **Real-time updates** — live results feed for spectator screens
- **Recently finished highlights** — visual callouts for new finishers

### Photo Gallery

- **Drag-and-drop upload** — batch upload up to 20 photos at once (JPG, PNG, WebP, GIF, max 10MB each)
- **Bib tagging** — tag photos with one or more bib numbers for participant lookup
- **Captions** — add descriptive text to photos
- **Search and filter** — find photos by bib number or caption text
- **Dual storage backends** — local filesystem or S3-compatible cloud storage (AWS S3, MinIO, DigitalOcean Spaces)
- **Results integration** — photo icons on results pages link directly to tagged photos

### User Accounts and Authentication

- **Magic link login** — passwordless email-based authentication
- **Session management** — 14-day sessions with automatic token rotation every 7 days
- **Role-based access control** — Admin (full access), Timer (timing console only), User (registration and profile)
- **User profile** — race history with statistics (total races, finishes, podiums, DNS/DNF counts), overall and category ranks per race
- **My Races page** — list of all registrations with bib, category, status, and links to results and photos
- **Settings** — change email, change password, set preferred locale
- **Sudo mode** — re-authentication required for sensitive account changes (20-minute window)
- **Login rate limiting** — max 5 attempts per 15 minutes per IP

### Admin Dashboard

- **Race dashboard** — list all races with status, quick actions, and detailed config views
- **User management** — view all users, change roles, with protection against removing the last admin
- **Audit logging** — tracks role changes, race modifications, and payment status changes with timestamps and metadata

### Internationalization (i18n)

- **Two languages** — English (default) and Swedish
- **Locale detection** — URL parameter, session preference, user setting, Accept-Language header, with fallback to English
- **Sticky locale** — preference saved to session and user profile
- **Full coverage** — all user-facing strings, status labels, date formatting, form options, and validation messages

### Real-Time Architecture

- **Phoenix PubSub** — timing events broadcast on per-race channels
- **LiveView** — all pages update in real-time without page refreshes
- **Multi-client sync** — timing console, results page, and kiosk mode all receive instant updates

## Project Structure

```
lib/
  bibtime/                    # Business logic (contexts)
    accounts/                 # User auth, sessions, roles
    races/                    # Race CRUD, categories, splits, templates
    participants/             # Participant management, bib assignment
    timing/                   # Split time recording, race starts, timing stations
    results/                  # Calculator + Ranker, CSV/PDF export
    registration/             # Public registration flow
    payments/                 # Stripe integration
    photos/                   # Photo upload and storage
    site_settings/            # Whitelabel site settings (singleton)
    audit_log/                # Audit logging
    mailer/                   # Swoosh email previews
  bibtime_web/                # Web layer
    live/
      admin/                  # Admin LiveView pages
      public/                 # Public LiveView pages
      dev/                    # Dev-only LiveViews (email previews)
    controllers/              # Traditional controllers (auth, payments, exports, station API)
    components/               # Shared UI components and layouts
    plugs/                    # SetLocale, RateLimiter, AssignSiteSettings
    helpers/                  # LocaleHelpers
bibtime_station/              # Standalone Pi-side OTP app (RFID reader → server)
hardware/                     # Hardware setup notes and R200 protocol research
assets/
  css/app.css                 # Tailwind CSS v4 config
  js/app.js                   # JavaScript entry point with hooks
priv/
  repo/migrations/            # Database migrations
  repo/seeds.exs              # Seed data
  gettext/                    # Translation files (en, sv)
```

## License

MIT — see [LICENSE](LICENSE).
