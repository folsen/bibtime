# Production compile-time config.
#
# All real per-deployment values (server URL, station token, reader
# device path) live in `config/runtime.exs` so they can be set via
# environment variables on the Pi without rebuilding the release.
import Config

config :bibtime_station,
  # The supervisor brings up the full Reader → ReadPipeline → Uplink →
  # Heartbeat tree on boot. This is the whole point of the prod build.
  start_supervision_tree: true,

  # Persistent buffer survives reboots — important for race day.
  buffer_persistent: true,
  buffer_path: "/var/lib/bibtime_station/read_buffer.dets"

config :logger, :default_handler, level: :info
