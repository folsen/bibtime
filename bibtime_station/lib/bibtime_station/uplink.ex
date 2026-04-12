defmodule BibtimeStation.Uplink do
  @moduledoc """
  Posts chip reads to the BibTime server.

  * `handle_cast({:send_read, read}, _)` — POSTs to
    `<base>/api/stations/<token>/reads`. On success, marks station
    online. On failure, enqueues to `BibtimeStation.Buffer` and marks
    offline.
  * Every 5 seconds (`:flush_buffer`), if online, drains up to 50 reads
    from the buffer and POSTs them in a batch to `/reads/batch`.

  HTTP calls are injectable via the `:http_client` init option so
  tests can mock them without hitting the network.
  """

  use GenServer
  require Logger

  @name __MODULE__
  @default_flush_interval_ms 5_000
  @batch_size 50

  # ---- public API ----

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc "Current online status. For introspection/tests."
  def online?(server \\ @name), do: GenServer.call(server, :online?)

  @doc "Force an immediate buffer flush. For tests."
  def flush(server \\ @name), do: GenServer.call(server, :flush_now)

  # ---- GenServer callbacks ----

  @impl true
  def init(opts) do
    client = Keyword.get(opts, :http_client, &__MODULE__.default_client/2)
    interval = Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms)
    buffer = Keyword.get(opts, :buffer, BibtimeStation.Buffer)
    schedule_flush? = Keyword.get(opts, :schedule_flush?, true)

    state = %{
      online: true,
      http_client: client,
      flush_interval_ms: interval,
      buffer: buffer
    }

    if schedule_flush?, do: schedule_flush(interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:send_read, read}, state) do
    payload = build_payload(read)

    case do_post(state.http_client, :single, [payload]) do
      :ok ->
        {:noreply, %{state | online: true}}

      {:error, reason} ->
        Logger.debug("[Uplink] send failed: #{inspect(reason)} — buffering")
        state.buffer.enqueue(payload)
        {:noreply, %{state | online: false}}
    end
  end

  @impl true
  def handle_call(:online?, _from, state), do: {:reply, state.online, state}

  def handle_call(:flush_now, _from, state) do
    state = do_flush(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:flush_buffer, state) do
    state = do_flush(state)
    schedule_flush(state.flush_interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---- helpers ----

  defp do_flush(state) do
    case state.buffer.drain(@batch_size) do
      [] ->
        state

      reads ->
        case do_post(state.http_client, :batch, reads) do
          :ok ->
            %{state | online: true}

          {:error, reason} ->
            Logger.debug("[Uplink] batch flush failed: #{inspect(reason)} — re-queueing")
            # Put them back — preserve insertion order.
            Enum.each(reads, fn r -> state.buffer.enqueue(r) end)
            %{state | online: false}
        end
    end
  end

  defp do_post(client, kind, payloads) do
    url = endpoint(kind)

    body =
      case kind do
        :single -> List.first(payloads)
        :batch -> %{reads: payloads}
      end

    client.(url, body)
  end

  defp endpoint(kind) do
    base = Application.fetch_env!(:bibtime_station, :bibtime_url)
    token = Application.fetch_env!(:bibtime_station, :station_token)

    case kind do
      :single -> "#{base}/api/stations/#{token}/reads"
      :batch -> "#{base}/api/stations/#{token}/reads/batch"
    end
  end

  defp build_payload(read) do
    %{
      chip_id: read.chip_id,
      read_at: read.read_at,
      rssi: Map.get(read, :rssi),
      read_count: Map.get(read, :read_count, 1)
    }
  end

  defp schedule_flush(interval), do: Process.send_after(self(), :flush_buffer, interval)

  @doc false
  def default_client(url, body) do
    case Req.post(url, json: body, retry: false, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
