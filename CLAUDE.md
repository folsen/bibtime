# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For project structure, data model, contexts, routes, and dependencies see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

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

## Database Notes

- SQLite with WAL mode. Dev: `bibtime_dev.db`, Test: `bibtime_test.db` (sandbox mode).
- Be aware of WAL mode locking. If database writes don't persist during QA, use sqlite3 directly as a workaround.

## Coding Guidelines

- Use `:req` for HTTP requests (not HTTPoison/Tesla)
- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>`
- Use `@current_scope.user` (not `@current_user`) in templates
- Use `<.icon>` for Heroicons, `<.input>` for form fields
- Use `to_form/2` for forms (never pass changesets directly to templates)
- Use LiveView streams for collections (not plain assigns)
- Never use `@apply` in CSS; write Tailwind classes directly
- No inline `<script>` tags; use colocated JS hooks (`:type={Phoenix.LiveView.ColocatedHook}`) or import into `app.js`
- Elixir: no index access on lists (`Enum.at` instead), no `if/elsif` (use `cond`/`case`), no nested modules in same file

## Internationalization (i18n)

All user-facing strings must go through gettext. Never hardcode display text.

- `gettext("...")` in templates/controllers; `ngettext(...)` for plurals
- Use `BibtimeWeb.LocaleHelpers` for status labels, date formatting, and select options
- After adding new strings: `mix gettext.extract --merge`
- Swedish translations: `priv/gettext/sv/LC_MESSAGES/default.po`

## When implementing new features

- When working from a TODO file (e.g. `PHASE4_TODO.md`), check off completed items (`- [ ]` → `- [x]`) as you finish each one.
- Always use the playwright-cli skill to run a QA pass after implementing anything. Come up with plan of how to test it, try to explore every codepath and possibility using playwright-cli and then report back a bullet point list of what you tested. Use the `test-server.sh` script to manage the test server as needed.
