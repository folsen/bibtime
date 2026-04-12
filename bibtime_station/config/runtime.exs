# Runtime config — evaluated each time the release boots on the Pi,
# NOT at build time. This means you can change BibTime URL, station
# token, etc. without rebuilding the firmware: just edit the systemd
# unit's environment variables (or /etc/default/bibtime_station) and
# `systemctl restart bibtime_station`.
#
# Each variable is required in :prod and falls back to whatever the
# compile-time config set in :dev / :test.
import Config

if config_env() == :prod do
  bibtime_url =
    System.get_env("BIBTIME_URL") ||
      raise """
      environment variable BIBTIME_URL is missing.
      Set it to the BibTime server base URL, e.g.
      `export BIBTIME_URL=http://192.168.1.231:4000`
      """

  station_token =
    System.get_env("STATION_TOKEN") ||
      raise """
      environment variable STATION_TOKEN is missing.
      Generate a token in the BibTime admin UI under
      /admin/races/:id/stations and export it as
      STATION_TOKEN=<token>.
      """

  reader_device = System.get_env("READER_DEVICE", "/dev/ttyUSB0")

  buffer_path =
    System.get_env("BUFFER_PATH", "/var/lib/bibtime_station/read_buffer.dets")

  config :bibtime_station,
    bibtime_url: bibtime_url,
    station_token: station_token,
    reader_device: reader_device,
    buffer_path: buffer_path
end
