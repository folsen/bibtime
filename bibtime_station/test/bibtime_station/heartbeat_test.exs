defmodule BibtimeStation.HeartbeatTest do
  use ExUnit.Case, async: false

  alias BibtimeStation.Heartbeat

  setup do
    Application.put_env(:bibtime_station, :bibtime_url, "http://localhost:9999")
    Application.put_env(:bibtime_station, :station_token, "test-token")
    :ok
  end

  test "tick/1 sends payload with the right shape and URL" do
    test_pid = self()

    client = fn url, payload ->
      send(test_pid, {:hb, url, payload})
      :ok
    end

    name = :"heartbeat_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Heartbeat.start_link(
        name: name,
        http_client: client,
        auto_tick?: false,
        interval_ms: 10_000
      )

    payload = Heartbeat.tick(name)

    assert_receive {:hb, url, ^payload}
    assert String.ends_with?(url, "/api/stations/test-token/heartbeat")

    assert is_integer(payload.uptime_seconds)
    assert payload.uptime_seconds >= 0
    assert is_binary(payload.firmware_version)
    assert payload.reads_total == 0
    assert payload.buffer_size == 0
    assert payload.reader_connected == false
  end

  test "auto-tick schedules heartbeat messages" do
    test_pid = self()

    client = fn _url, _payload ->
      send(test_pid, :hb_sent)
      :ok
    end

    name = :"heartbeat_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Heartbeat.start_link(
        name: name,
        http_client: client,
        auto_tick?: true,
        interval_ms: 20
      )

    assert_receive :hb_sent, 200
    assert_receive :hb_sent, 200
  end
end
