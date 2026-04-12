defmodule BibtimeStation.ReaderTest do
  @moduledoc """
  Behavioural tests for `BibtimeStation.Reader` that don't need real
  hardware. Focused on the resilience contract: when the serial device
  is missing, the GenServer must NOT crash — it must log, schedule a
  retry, and stay alive so the rest of the supervision tree keeps
  running.
  """

  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias BibtimeStation.Reader

  setup do
    # Make sure tests use a tiny retry interval and a guaranteed-missing
    # device path. Restore previous values after the test.
    prev_device = Application.get_env(:bibtime_station, :reader_device)
    prev_retry = Application.get_env(:bibtime_station, :reader_retry_open_ms)
    prev_skip = Application.get_env(:bibtime_station, :reader_skip_open)

    Application.put_env(:bibtime_station, :reader_device, "/dev/this-device-does-not-exist-#{System.unique_integer([:positive])}")
    Application.put_env(:bibtime_station, :reader_retry_open_ms, 50)
    Application.put_env(:bibtime_station, :reader_skip_open, false)

    on_exit(fn ->
      restore(:reader_device, prev_device)
      restore(:reader_retry_open_ms, prev_retry)
      restore(:reader_skip_open, prev_skip)
    end)

    :ok
  end

  defp restore(_key, nil), do: :ok
  defp restore(key, val), do: Application.put_env(:bibtime_station, key, val)

  test "stays alive and logs when the serial device is missing" do
    log =
      capture_log(fn ->
        {:ok, pid} = Reader.start_link(name: :reader_under_test)

        # Give it time to attempt the open and schedule a retry.
        Process.sleep(150)

        assert Process.alive?(pid),
               "Reader must not crash when the device is missing"

        GenServer.stop(pid, :normal, 1_000)
      end)

    assert log =~ "could not open"
    assert log =~ "retrying in"
  end

  test "retries periodically while device is missing" do
    log =
      capture_log(fn ->
        {:ok, pid} = Reader.start_link(name: :reader_retry_test)

        # 50ms retry interval × ~5 attempts = 250ms
        Process.sleep(300)

        assert Process.alive?(pid),
               "Reader must remain alive across multiple retry attempts"

        GenServer.stop(pid, :normal, 1_000)
      end)

    # We expect at least 2 "could not open" messages because we waited
    # long enough for multiple retry cycles.
    open_attempts =
      log
      |> String.split("\n")
      |> Enum.count(&String.contains?(&1, "could not open"))

    assert open_attempts >= 2,
           "Expected multiple open attempts in the log, got #{open_attempts}:\n#{log}"
  end
end
