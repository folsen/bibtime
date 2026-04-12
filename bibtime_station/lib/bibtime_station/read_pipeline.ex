defmodule BibtimeStation.ReadPipeline do
  @moduledoc """
  Receives raw tag reads from `BibtimeStation.Reader`, de-duplicates them
  within a configurable time window (default 5 seconds), and forwards
  unique reads to `BibtimeStation.Uplink` via cast.

  Also tracks a cumulative count of unique reads processed since boot
  (queryable via `read_count/0`) — used by `BibtimeStation.Heartbeat`.
  """

  use GenServer

  @name __MODULE__
  @default_window_ms 5_000

  # ---- public API ----

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @spec read_count() :: non_neg_integer()
  def read_count(server \\ @name), do: GenServer.call(server, :read_count)

  @doc "Reset dedup state and counters. Mainly for tests."
  def reset(server \\ @name), do: GenServer.call(server, :reset)

  # ---- GenServer callbacks ----

  @impl true
  def init(opts) do
    window = Keyword.get(opts, :dedup_window_ms) ||
               Application.get_env(:bibtime_station, :read_dedup_window_ms, @default_window_ms)

    target = Keyword.get(opts, :uplink, BibtimeStation.Uplink)
    clock = Keyword.get(opts, :clock, &default_clock/0)

    {:ok,
     %{
       recent: %{},
       window_ms: window,
       count: 0,
       uplink: target,
       clock: clock
     }}
  end

  @impl true
  def handle_cast({:tag_read, read}, state) do
    now = state.clock.()
    chip_id = read.chip_id

    case Map.get(state.recent, chip_id) do
      last when is_integer(last) and now - last <= state.window_ms ->
        # Duplicate within window — drop.
        {:noreply, state}

      _ ->
        dispatch(state.uplink, read)
        new_recent = prune(state.recent, now, state.window_ms) |> Map.put(chip_id, now)
        {:noreply, %{state | recent: new_recent, count: state.count + 1}}
    end
  end

  @impl true
  def handle_call(:read_count, _from, state), do: {:reply, state.count, state}

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | recent: %{}, count: 0}}
  end

  # ---- helpers ----

  defp dispatch(target, read) do
    GenServer.cast(target, {:send_read, read})
  end

  defp prune(recent, now, window_ms) do
    cutoff = now - window_ms
    for {k, v} <- recent, v >= cutoff, into: %{}, do: {k, v}
  end

  defp default_clock, do: System.monotonic_time(:millisecond)
end
