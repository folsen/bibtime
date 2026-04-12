defmodule BibtimeStation.Heartbeat do
  @moduledoc """
  Periodically PUTs status metadata to the BibTime server's
  `/api/stations/:token/heartbeat` endpoint.

  Payload:

      %{
        firmware_version: "0.1.0",
        uptime_seconds: 1234,
        reads_total: 42,
        buffer_size: 0,
        reader_connected: true
      }

  Errors are logged and otherwise ignored — the next tick will retry.
  """

  use GenServer
  require Logger

  @name __MODULE__
  @default_interval_ms 10_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc "Force an immediate heartbeat tick. Returns the payload that was sent."
  def tick(server \\ @name), do: GenServer.call(server, :tick)

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms) ||
        Application.get_env(:bibtime_station, :heartbeat_interval_ms, @default_interval_ms)

    client = Keyword.get(opts, :http_client, &__MODULE__.default_client/2)
    started_at = System.monotonic_time(:millisecond)
    schedule? = Keyword.get(opts, :auto_tick?, true)

    if schedule?, do: schedule_next(interval)

    {:ok,
     %{
       interval_ms: interval,
       http_client: client,
       started_at: started_at
     }}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    _ = send_heartbeat(state)
    schedule_next(state.interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:tick, _from, state) do
    payload = build_payload(state)
    _ = state.http_client.(endpoint(), payload)
    {:reply, payload, state}
  end

  # ---- helpers ----

  defp send_heartbeat(state) do
    payload = build_payload(state)

    case state.http_client.(endpoint(), payload) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("[Heartbeat] send failed: #{inspect(reason)}")
        :error
    end
  end

  defp build_payload(state) do
    now = System.monotonic_time(:millisecond)

    %{
      firmware_version: firmware_version(),
      uptime_seconds: div(now - state.started_at, 1000),
      reads_total: safe_read_count(),
      buffer_size: safe_buffer_size(),
      reader_connected: reader_alive?()
    }
  end

  defp firmware_version do
    case Application.spec(:bibtime_station, :vsn) do
      nil -> "0.0.0"
      vsn -> to_string(vsn)
    end
  end

  defp safe_read_count do
    case Process.whereis(BibtimeStation.ReadPipeline) do
      nil -> 0
      _pid -> BibtimeStation.ReadPipeline.read_count()
    end
  end

  defp safe_buffer_size do
    case Process.whereis(BibtimeStation.Buffer) do
      nil -> 0
      _pid -> BibtimeStation.Buffer.size()
    end
  end

  defp reader_alive? do
    case Process.whereis(BibtimeStation.Reader) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp endpoint do
    base = Application.fetch_env!(:bibtime_station, :bibtime_url)
    token = Application.fetch_env!(:bibtime_station, :station_token)
    "#{base}/api/stations/#{token}/heartbeat"
  end

  defp schedule_next(interval), do: Process.send_after(self(), :heartbeat, interval)

  @doc false
  def default_client(url, payload) do
    case Req.put(url, json: payload, retry: false, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
