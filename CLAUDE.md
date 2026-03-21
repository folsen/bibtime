# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BibTime is a self-hosted race timing platform built with Elixir/Phoenix 1.8 + LiveView, using SQLite (via `ecto_sqlite3`) for single-file deployment simplicity. It handles race management, participant registration, real-time timing, and live results with kiosk display mode.

## Common Commands

```bash
mix setup                  # Install deps, create DB, run migrations, seed, build assets
mix phx.server             # Start dev server on port 4000
mix test                   # Run all tests (auto-creates/migrates DB)
mix test path/to/test.exs  # Run a single test file
mix test --failed          # Re-run only failed tests
mix precommit              # Full QA: compile (warnings-as-errors), unused deps, format, test
mix ecto.gen.migration name # Generate a new migration
mix ecto.reset             # Drop + recreate + seed database
scripts/test-server.sh start|stop|status|restart  # Manage test server on port 4001
```

**Always run `mix precommit` before committing.** The `precommit` alias runs in the `:test` env.

## Architecture

### Contexts (Business Logic Layer)

All business logic lives in context modules under `lib/bibtime/`:

| Context | Purpose |
|---------|---------|
| `Bibtime.Accounts` | User auth (bcrypt, phx.gen.auth) |
| `Bibtime.Races` | Race CRUD, categories, auto-categories, splits, templates |
| `Bibtime.Participants` | Competitor management, bib assignment, status tracking |
| `Bibtime.Timing` | Split time recording, race starts, PubSub broadcasting |
| `Bibtime.Results` | Results calculation (Calculator) + ranking (Ranker) |
| `Bibtime.Registration` | Public registration flow, auto bib/user creation |

### Data Model

- **Race** → has_many categories, auto_categories, splits, participants, race_starts
- **Participant** → belongs_to race, race_category, user; has_many split_times
- **SplitTime** → belongs_to participant, split
- Race statuses: `draft → registration_open → registration_closed → in_progress → finished → archived`
- Participant statuses: `registered → racing → dns/dnf/dsq/finished`

### Real-Time Updates

Timing events broadcast via PubSub on `"race:timing:#{race_id}"`. Results LiveView and Kiosk LiveView subscribe and re-rank on `{:split_time_recorded, split_time}` and `{:split_time_deleted, split_time}` messages.

### Web Layer (`lib/bibtime_web/`)

**Route structure** (see `router.ex`):
- Public: `/races/:slug`, `/races/:slug/results`, `/races/:slug/register`
- Kiosk: `/races/:slug/kiosk` (fullscreen layout, no nav)
- Admin: `/admin/races/*` (requires `require_authenticated_user` + `require_admin_user`)
- Authenticated: `/profile`, `/my-races`
- Auth: `/users/log-in`, `/users/log-out`

**Layouts**: `app` (public), `admin` (sidebar nav), `kiosk` (fullscreen), `kiosk_root`

**LiveViews** are organized under `lib/bibtime_web/live/admin/` and `lib/bibtime_web/live/public/`.

### Frontend

- **Tailwind CSS v4** — configured in `assets/css/app.css` (no `tailwind.config.js`)
- **esbuild** — bundles `assets/js/app.js`
- Custom DaisyUI-style theme with light/dark modes
- Fonts: DM Sans (body), DM Mono (timing data)
- Heroicons via `<.icon name="hero-x-mark" />` component

### Database

SQLite with WAL mode. Dev: `bibtime_dev.db`, Test: `bibtime_test.db` (sandbox mode).

## Key Guidelines from AGENTS.md

- Use `:req` for HTTP requests (not HTTPoison/Tesla)
- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>`
- Use `@current_scope.user` (not `@current_user`) in templates
- Use `<.icon>` for Heroicons, `<.input>` for form fields
- Use `to_form/2` for forms (never pass changesets directly to templates)
- Use LiveView streams for collections (not plain assigns)
- Never use `@apply` in CSS; write Tailwind classes directly
- No inline `<script>` tags; use colocated JS hooks (`:type={Phoenix.LiveView.ColocatedHook}`) or import into `app.js`
- Elixir: no index access on lists (`Enum.at` instead), no `if/elsif` (use `cond`/`case`), no nested modules in same file

## When implementing new features

- Always use the playwright-cli skill to run a QA pass after implementing anything. Come up with plan of how to test it, try to explore every codepath and possibility using playwright-cli and then report back a bullet point list of what you tested. Use the `test-server.sh` script to manage the test server as needed.
