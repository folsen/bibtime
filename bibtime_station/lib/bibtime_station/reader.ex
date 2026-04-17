defmodule BibtimeStation.Reader do
  @moduledoc """
  GenServer that owns the R200 serial port.

  * Opens the configured device in active mode via `Circuits.UART`.
  * On macOS host, runs the CH340 "wake" sequence (brief 9600 baud
    connect) before reopening at 115200.
  * Configures the reader: region = EU, TX power from config.
  * Starts continuous inventory and forwards parsed tag frames to
    `BibtimeStation.ReadPipeline` via `GenServer.cast`.

  Serial errors cause the GenServer to crash — the supervisor restarts
  it, which re-opens the port.

  In `Mix.env() == :test` the Reader starts but does **not** open the
  serial port (so tests don't fight over `/dev/tty*`).
  """

  use GenServer
  require Logger

  alias Circuits.UART
  alias BibtimeStation.Reader.Protocol

  @name __MODULE__

  # If no UART data arrives within this window, assume inventory has
  # stopped and restart it. The R200 sends ~70 frames/sec even with no
  # tags in range (0x15 "no tag found"), so 5s of complete silence is a
  # reliable signal that something is wrong.
  @watchdog_timeout_ms 5_000
  @watchdog_check_ms 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc "Stop any in-progress inventory. Used from tests and IEx."
  def stop_inventory(server \\ @name) do
    GenServer.call(server, :stop_inventory)
  end

  @doc "Returns `true` when the UART port is open and reading."
  def port_open?(server \\ @name) do
    GenServer.call(server, :port_open?)
  catch
    :exit, _ -> false
  end

  # -------- GenServer callbacks --------

  @impl true
  def init(opts) do
    test_env? = Application.get_env(:bibtime_station, :reader_skip_open, false)

    if test_env? do
      {:ok, %{uart: nil, opts: opts, opened?: false, last_data_at: nil}}
    else
      {:ok, pid} = UART.start_link()
      state = %{uart: pid, opts: opts, opened?: false, last_data_at: nil}
      {:ok, state, {:continue, :open_port}}
    end
  end

  # Default backoff between retry attempts when the serial device is
  # missing or otherwise unavailable. Overridable via the
  # :reader_retry_open_ms application env (used by tests).
  @retry_open_ms 5_000

  defp retry_open_ms do
    Application.get_env(:bibtime_station, :reader_retry_open_ms, @retry_open_ms)
  end

  @impl true
  def handle_continue(:open_port, %{uart: pid} = state) do
    device = Application.fetch_env!(:bibtime_station, :reader_device)
    baud = Application.get_env(:bibtime_station, :reader_baud, 115_200)
    power = Application.get_env(:bibtime_station, :read_power_cdbm, 2000)

    maybe_wake(pid, device)

    case UART.open(pid, device,
           speed: baud,
           active: true,
           framing: {BibtimeStation.Reader.Framer, []},
           rtscts: false,
           flow_control: :none
         ) do
      :ok ->
        # Ensure DTR/RTS off — the M100 misbehaves otherwise.
        try do
          UART.set_dtr(pid, false)
          UART.set_rts(pid, false)
        rescue
          _ -> :ok
        end

        # Ignore any garbage from the wake sequence.
        UART.flush(pid, :receive)

        Logger.info("[Reader] opened #{device} @ #{baud}")

        :ok = UART.write(pid, Protocol.set_region(:eu))
        Process.sleep(50)
        :ok = UART.write(pid, Protocol.set_power(power))
        Process.sleep(50)
        :ok = UART.write(pid, Protocol.multi_inventory(0xFFFF))

        schedule_watchdog()
        now = System.monotonic_time(:millisecond)
        {:noreply, %{state | opened?: true, last_data_at: now}}

      {:error, reason} ->
        # Don't crash — the rest of the supervision tree (Uplink,
        # Heartbeat) should keep running and report
        # `reader_connected: false` so the dashboard sees the
        # station as online but unhappy. Retry on a timer.
        ms = retry_open_ms()

        Logger.warning(
          "[Reader] could not open #{device}: #{inspect(reason)} — retrying in #{ms}ms"
        )

        Process.send_after(self(), :retry_open, ms)
        {:noreply, %{state | opened?: false}}
    end
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, %{uart: pid} = state) do
    Logger.error("[Reader] UART error: #{inspect(reason)} — closing and retrying")

    # Close the port (it's likely in a bad state) and schedule a retry.
    try do
      UART.close(pid)
    rescue
      _ -> :ok
    end

    Process.send_after(self(), :retry_open, retry_open_ms())
    {:noreply, %{state | opened?: false}}
  end

  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    handle_frame(data)
    {:noreply, %{state | last_data_at: System.monotonic_time(:millisecond)}}
  end

  def handle_info(:inventory_watchdog, %{opened?: false} = state) do
    {:noreply, state}
  end

  def handle_info(:inventory_watchdog, %{uart: pid, last_data_at: last} = state) do
    now = System.monotonic_time(:millisecond)
    silent_ms = now - (last || 0)

    if silent_ms >= @watchdog_timeout_ms do
      Logger.warning(
        "[Reader] no data for #{div(silent_ms, 1000)}s — restarting inventory"
      )

      _ = UART.write(pid, Protocol.stop_inventory())
      Process.sleep(50)
      :ok = UART.write(pid, Protocol.multi_inventory(0xFFFF))
    end

    schedule_watchdog()
    {:noreply, %{state | last_data_at: if(silent_ms >= @watchdog_timeout_ms, do: now, else: last)}}
  end

  def handle_info(:retry_open, state) do
    {:noreply, state, {:continue, :open_port}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:port_open?, _from, state) do
    {:reply, state.opened?, state}
  end

  def handle_call(:stop_inventory, _from, %{uart: nil} = state), do: {:reply, :ok, state}

  def handle_call(:stop_inventory, _from, %{uart: pid} = state) do
    _ = UART.write(pid, Protocol.stop_inventory())
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, %{uart: pid}) when is_pid(pid) do
    try do
      _ = UART.write(pid, Protocol.stop_inventory())
      :ok = UART.close(pid)
    rescue
      _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  # -------- helpers --------

  # The framer hands us one complete raw frame binary at a time.
  defp handle_frame(raw) do
    case Protocol.parse_frame(raw) do
      {:ok, %{type: 0x02, cmd: 0x22, params: params}, _rest} ->
        case Protocol.parse_tag(params) do
          {:ok, tag} ->
            read = %{
              chip_id: tag.epc,
              rssi: tag.rssi,
              read_at: DateTime.utc_now()
            }

            GenServer.cast(BibtimeStation.ReadPipeline, {:tag_read, read})

          :error ->
            :ok
        end

      {:ok, %{type: 0x01, cmd: 0xFF, params: <<code>>}, _rest} when code in [0x15, 0x17] ->
        :ok

      {:ok, %{type: 0x01, cmd: 0xFF, params: <<code>>}, _rest} ->
        Logger.info("[Reader] error frame: code=0x#{Integer.to_string(code, 16)}")

      {:ok, %{type: type, cmd: cmd, params: params}, _rest} ->
        Logger.info(
          "[Reader] frame: type=0x#{Integer.to_string(type, 16)}" <>
            " cmd=0x#{Integer.to_string(cmd, 16)}" <>
            " params=#{Base.encode16(params)}"
        )

      {:error, reason} ->
        Logger.warning("[Reader] parse error: #{inspect(reason)}")

      {:more, _} ->
        :ok
    end
  end

  defp schedule_watchdog do
    Process.send_after(self(), :inventory_watchdog, @watchdog_check_ms)
  end

  defp maybe_wake(pid, device) do
    if macos_host?() do
      Logger.debug("[Reader] running CH340 wake sequence")

      case UART.open(pid, device, speed: 9600, active: false) do
        :ok ->
          try do
            UART.set_dtr(pid, false)
            UART.set_rts(pid, false)
          rescue
            _ -> :ok
          end

          Process.sleep(200)
          _ = UART.write(pid, Protocol.get_version(:hardware))
          Process.sleep(200)
          _ = UART.drain(pid)
          _ = UART.flush(pid, :receive)
          :ok = UART.close(pid)
          Process.sleep(200)

        {:error, reason} ->
          Logger.warning("[Reader] wake open failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  # The CH340 wake quirk only matters on macOS — Linux's CH340 driver
  # doesn't need it. Detect at runtime so the same release works on
  # both dev (Mac) and prod (Pi).
  @doc false
  def macos_host? do
    :os.type() == {:unix, :darwin}
  end
end
