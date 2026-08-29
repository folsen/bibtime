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

  # R200/M100 TX power in centi-dBm. The board tops out at 2600
  # (26.00 dBm); the stock default of 2000 (20.00 dBm) is deliberately
  # conservative. Raising it roughly doubles read range per 6 dB but
  # also raises current draw — back off if the USB hub browns out.
  read_power_cdbm =
    case System.get_env("READ_POWER_CDBM") do
      nil ->
        2000

      raw ->
        case Integer.parse(raw) do
          {cdbm, ""} when cdbm >= 0 and cdbm <= 2600 ->
            cdbm

          _ ->
            raise """
            READ_POWER_CDBM must be an integer between 0 and 2600
            (centi-dBm), e.g. READ_POWER_CDBM=2600 for the M100's
            maximum of 26.00 dBm. Got: #{inspect(raw)}
            """
        end
    end

  config :bibtime_station,
    bibtime_url: bibtime_url,
    station_token: station_token,
    reader_device: reader_device,
    buffer_path: buffer_path,
    read_power_cdbm: read_power_cdbm
end
