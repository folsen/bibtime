# Test config — fast, isolated, no real I/O.
import Config

config :bibtime_station,
  # Tests start their own GenServers with explicit options. The
  # supervisor must NOT auto-start, or it would fight with tests over
  # the serial port and ETS tables.
  start_supervision_tree: false,
  reader_device: "/dev/null",
  bibtime_url: "http://test.invalid",
  station_token: "test-token",
  buffer_persistent: false

config :logger, :default_handler, level: :warning
