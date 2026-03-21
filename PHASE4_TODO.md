# Phase 4 — Advanced Features

## 1. Race Templates

Pre-configured split/category setups so organizers don't rebuild from scratch each time.

- [x] Design `race_templates` table (name, description, race_type, splits JSON, categories JSON)
- [x] Seed built-in templates: Standard Triathlon (Olympic), Sprint Triathlon, 5K/10K/Half/Marathon, Duathlon, Aquathlon
- [x] Admin UI: "Create race from template" option on race creation page
- [x] Auto-populate splits and categories when a template is selected
- [x] Admin UI: "Save as template" button on an existing race's settings page
- [x] Admin UI: "Clone from previous race" — pick any past race and copy its splits, categories, and config
- [x] Allow editing template defaults (admin-only template management page)

## 2. Kiosk / Big-Screen Display Mode

A venue-friendly fullscreen leaderboard for projectors and TVs at the race site.

- [x] New route: `/races/:slug/kiosk` — fullscreen results view, no nav/header/footer
- [x] Large fonts, high contrast, optimized for readability at distance
- [x] Auto-scroll: slowly scroll through results, loop back to top
- [x] Configurable display: choose which columns to show (rank, bib, name, total, status)
- [x] Category rotation: cycle through Overall → Cat 1 → Cat 2 → ... on a timer
- [x] Flash animation when a new finisher comes in (PubSub-driven, same as results page)
- [x] Admin setting: kiosk refresh interval, scroll speed, theme (light/dark)
- [x] Support `?category=X&scroll_speed=slow&theme=dark` URL params for easy configuration

## 3. Participant Profiles & Result History

Let participants see their performance across multiple races.

- [x] New route: `/profile` — logged-in user's personal results dashboard
- [x] List all races the user has participated in (via user_id → participants → races)
- [x] Show finish time, rank (overall + category), and split breakdown per race
- [x] Profile page shows aggregate stats: races completed, podium finishes, DNS/DNF rate

## 4. Photo Integration

Link finish-line and course photos to bib numbers for participants to find their photos.

- [ ] Design `race_photos` table (race_id, file_path/url, bib_numbers array, split_id, timestamp)
- [ ] Admin: bulk photo upload interface (drag-and-drop multiple files)
- [ ] Store photos in S3-compatible object storage
- [ ] Add `waffle` or `arc` dependency for file upload handling
- [ ] Manual bib tagging: admin interface to tag bib numbers on uploaded photos
- [ ] Display photos on participant result rows (thumbnail + lightbox)
- [ ] Public: photo gallery page per race (`/races/:slug/photos`)
- [ ] Filter photos by bib number or participant name
- [ ] Show photos on the "My Races" detail view for logged-in participants
- [ ] Future: OCR-based auto-detection of bib numbers from photos (stretch goal)

## 5. Payment Integration (Stripe)

Enable paid race registration for events that charge an entry fee.

- [ ] Add `stripity_stripe` dependency
- [ ] Add payment fields to race config: `entry_fee_cents`, `currency`, `payment_required` boolean
- [ ] Design `payments` table (participant_id, race_id, stripe_payment_intent_id, amount_cents, currency, status, paid_at)
- [ ] Registration flow: after form submission, redirect to Stripe Checkout for paid races
- [ ] Handle Stripe webhook for payment confirmation (mark payment as completed)
- [ ] Only confirm registration after successful payment (pending state until paid)
- [ ] Admin: have ability to set single-tier early-bird pricing structure or flat rate
- [ ] Admin: payment overview page per race — total collected, pending, refunded
- [ ] Admin: manual refund button (triggers Stripe refund API)
- [ ] Admin: free/comp registration override (skip payment for specific participants)
- [ ] Support Stripe Connect for multi-organizer setups (stretch goal)
- [ ] Receipt emails sent after successful payment

## 6. Internationalization (Swedish + English)

The app should work in both Swedish and English since the target audience is Nordic race organizers.

- [x] Mark all user-facing strings in templates with `gettext()` / `dgettext()`
- [x] Create Swedish locale: `priv/gettext/sv/LC_MESSAGES/default.po`
- [x] Translate all UI strings: nav, buttons, form labels, status badges, flash messages
- [x] Translate email templates (registration confirmation, login instructions)
- [x] Translate results page headers and export CSV headers
- [x] Language switcher in the nav bar (flag icons or SV/EN toggle)
- [x] Store locale preference in user settings (persisted) and session (for anonymous users)
- [x] Per-race locale setting: allow organizers to set default language for their race's public pages
- [x] Date/time formatting respects locale (Swedish: "20 mars 2026", English: "March 20, 2026")
- [x] Pluralization rules for both languages

## 7. Admin User Management

Allow existing admins to promote other users, instead of requiring direct DB access.

- [x] Admin page: `/admin/users` — list all users with role indicators
- [x] Toggle admin role from the user list (promote/demote)
- [x] Prevent removing admin from yourself (last-admin protection)
- [x] Activity log: track admin actions (race created, participant edited, user promoted) in an `audit_log` table
- [x] Add timing-only role for volunteers

## 8. Deployment & Self-Hosting

Make it trivial for someone to deploy their own BibTime instance.

- [x] Create a `Dockerfile` (multi-stage build: deps → compile → release → runtime)
- [x] Create `docker-compose.yml` for single-command local deployment
- [x] Create `fly.toml` for one-click Fly.io deployment
- [x] Add release scripts: `rel/overlays/bin/server`, `rel/overlays/bin/migrate`
- [x] Write deployment guide covering: Docker, Fly.io, bare metal (systemd)
- [x] Add health check endpoint (`/healthz`) for load balancers
- [x] Backup/restore script for SQLite database file
- [x] Environment variable documentation (all configurable settings in one place)

## Priority Order (suggested)

1. **Race Templates** — high impact, low effort, makes the app much more usable
2. **Kiosk Mode** — essential for race day, mostly UI work
3. **Admin User Management** — small scope, needed for multi-person operations
4. **Internationalization** — important for Nordic market, Gettext is already wired up
5. **Deployment** — needed before anyone else can self-host
6. **Participant Profiles** — nice-to-have, adds long-term stickiness
7. **Photo Integration** — significant effort, requires file storage decisions
8. **Payment Integration** — largest scope, only needed for paid events
