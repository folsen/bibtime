import Config

# Staging inherits all production settings (SSL, cache manifest, logger level),
# then re-enables the Swoosh local mailbox so staging can inspect sent mail at
# /dev/mailbox without delivering real email. Since releases share a single
# compile-time env, staging is a distinct MIX_ENV built via fly.staging.toml.
import_config "prod.exs"

# Mount /dev/mailbox and /dev/dashboard (compile-time gated in the router).
config :bibtime, dev_routes: true

# Override prod.exs — keep the Swoosh.Adapters.Local.Storage.Memory GenServer
# running so the Local adapter can enqueue mail without crashing.
config :swoosh, local: true
