# Development config — running on a Mac via `iex -S mix`.
import Config

# On the dev machine the R200 is plugged in via USB. macOS exposes it
# as /dev/cu.usbserial-XXXX (number depends on which USB port). Update
# this whenever you swap ports — `ls /dev/cu.usbserial-*` will tell
# you the current path.
config :bibtime_station,
  reader_device: "/dev/cu.usbserial-11330",
  bibtime_url: "http://localhost:4000",
  station_token: "dev-token-replace-me",

  # Don't auto-start the supervisor in dev — let the developer choose
  # when to bring it up via `Application.put_env(...)` + manual start,
  # so plain `iex -S mix` doesn't grab the serial port.
  start_supervision_tree: false,

  # Disk-backed buffer is overkill in dev; ETS is fine.
  buffer_persistent: false

config :logger, :default_handler, level: :debug
