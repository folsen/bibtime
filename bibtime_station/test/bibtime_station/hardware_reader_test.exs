defmodule BibtimeStation.HardwareReaderTest do
  @moduledoc """
  Integration test against a real R200/M100 reader.

  Skipped by default. Run with:

      mix test --only hardware

  Reads the device path from the `HARDWARE_READER_DEVICE` env var,
  falling back to `/dev/cu.usbserial-11330` (the dev config default
  for a Mac). Override when invoking:

      HARDWARE_READER_DEVICE=/dev/cu.usbserial-1120 mix test --only hardware

  This test does NOT use the full `BibtimeStation.Reader` GenServer — it
  opens the port directly, runs the macOS CH340 wake sequence, sends a
  get-version command, and verifies the response identifies the M100
  board. Explicitly stops inventory on exit just in case.
  """

  use ExUnit.Case, async: false
  @moduletag :hardware

  alias Circuits.UART
  alias BibtimeStation.Reader.Protocol

  @default_device "/dev/cu.usbserial-11330"

  test "opens the R200 and fetches the firmware version" do
    device = System.get_env("HARDWARE_READER_DEVICE", @default_device)

    unless File.exists?(device) do
      flunk("reader device not present: #{device}")
    end

    {:ok, uart} = UART.start_link()

    # --- CH340 wake sequence (macOS) ---
    :ok = UART.open(uart, device, speed: 9600, active: false)
    _ = safe_dtr_rts(uart)
    Process.sleep(200)
    _ = UART.write(uart, Protocol.get_version(:hardware))
    Process.sleep(200)
    _ = UART.drain(uart)
    _ = UART.flush(uart, :both)
    :ok = UART.close(uart)
    Process.sleep(200)

    # --- Real open at 115200 in passive mode ---
    :ok = UART.open(uart, device, speed: 115_200, active: false)
    _ = safe_dtr_rts(uart)
    Process.sleep(200)
    _ = UART.flush(uart, :both)

    # Send explicit stop-inventory first in case we left the reader running.
    _ = UART.write(uart, Protocol.stop_inventory())
    Process.sleep(200)
    _ = UART.flush(uart, :receive)

    # Get hardware version.
    :ok = UART.write(uart, Protocol.get_version(:hardware))
    {:ok, response} = collect(uart, <<>>, 1000)

    assert {:ok, frame, _rest} = Protocol.parse_frame(response),
           "failed to parse response: #{inspect(response, limit: :infinity)}"

    assert frame.type == 0x01
    assert frame.cmd == 0x03

    # Expect the ASCII identification string.
    printable = for <<c <- frame.params>>, c >= 32 and c < 127, into: "", do: <<c>>

    assert printable =~ "M100" or printable =~ "V1.0",
           "unexpected version string: #{inspect(printable)}"

    # Be nice to the reader — stop any inventory.
    _ = UART.write(uart, Protocol.stop_inventory())
    Process.sleep(100)
    _ = UART.close(uart)
  end

  defp safe_dtr_rts(uart) do
    try do
      UART.set_dtr(uart, false)
      UART.set_rts(uart, false)
    rescue
      _ -> :ok
    end
  end

  # Poll read with a deadline and keep accumulating until we see the DD end marker.
  defp collect(uart, acc, deadline_ms) do
    started = System.monotonic_time(:millisecond)
    do_collect(uart, acc, started + deadline_ms)
  end

  defp do_collect(uart, acc, deadline) do
    now = System.monotonic_time(:millisecond)

    cond do
      byte_size(acc) > 0 and :binary.match(acc, <<0xDD>>) != :nomatch ->
        {:ok, acc}

      now >= deadline ->
        if byte_size(acc) > 0, do: {:ok, acc}, else: {:error, :timeout}

      true ->
        remaining = max(deadline - now, 10)

        case UART.read(uart, remaining) do
          {:ok, <<>>} ->
            do_collect(uart, acc, deadline)

          {:ok, chunk} when is_binary(chunk) ->
            do_collect(uart, acc <> chunk, deadline)

          {:error, _} = err ->
            err
        end
    end
  end
end
