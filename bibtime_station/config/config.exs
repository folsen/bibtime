# Common compile-time config — applies to all Mix environments.
import Config

# Defaults for the BibTime station application. Per-environment files
# below override these (and `config/runtime.exs` overrides them all).
config :bibtime_station,
  # Serial port settings for the R200 reader. Defaults to USB serial
  # at /dev/ttyUSB0 — what stock Raspberry Pi OS will expose when an
  # M100/CH340-based dev board is plugged in.
  reader_device: "/dev/ttyUSB0",
  reader_baud: 115_200,
  read_power_cdbm: 2000,

  # ReadPipeline dedup window
  read_dedup_window_ms: 5_000,

  # Heartbeat interval to BibTime server
  heartbeat_interval_ms: 10_000,

  # Persistent offline buffer file. Override per environment.
  buffer_path: "/tmp/bibtime_station_buffer.dets",

  # Whether to use a disk-backed (DETS) buffer or in-memory ETS.
  # Production overrides this to `true`.
  buffer_persistent: false,

  # Whether the application supervisor starts the full pipeline on
  # boot. Tests and dev iex sessions default to false; prod sets it
  # to true.
  start_supervision_tree: false

# Send all logs through the standard :logger; release sets the prod
# logger backend at runtime.
config :logger, :default_handler, level: :info

import_config "#{config_env()}.exs"
