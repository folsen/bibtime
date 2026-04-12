defmodule BibtimeStation.Buffer do
  @moduledoc """
  Offline read buffer for chip reads that the `Uplink` couldn't post
  to the BibTime server (e.g. WiFi dropped, server unreachable). The
  uplink drains this buffer in batches when connectivity returns.

  Backed by either ETS (in-memory) or DETS (disk-backed file). The
  choice is runtime-configurable via the `:buffer_persistent` and
  `:buffer_path` application env keys:

  * `buffer_persistent: false` → ETS — fast, in-memory, lost on
    restart. The default for tests and dev iex sessions.
  * `buffer_persistent: true`  → DETS — disk-backed at `:buffer_path`,
    survives reboots. Used in production on the Pi (the prod config
    sets the path to `/var/lib/bibtime_station/read_buffer.dets`).

  Each entry is keyed by a monotonically increasing sequence number so
  that `drain/1` returns reads in insertion order.
  """

  use GenServer

  @name __MODULE__

  # ------- public API -------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @spec enqueue(map()) :: :ok
  def enqueue(read), do: GenServer.call(@name, {:enqueue, read})

  @spec drain(pos_integer()) :: [map()]
  def drain(count) when is_integer(count) and count > 0,
    do: GenServer.call(@name, {:drain, count})

  @spec size() :: non_neg_integer()
  def size, do: GenServer.call(@name, :size)

  @doc "Clear the buffer. Mainly for tests."
  def clear, do: GenServer.call(@name, :clear)

  # ------- GenServer callbacks -------

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :bibtime_station_buffer)

    # Use the per-instance opt if provided (tests pass this), otherwise
    # fall back to application env so the prod boot picks up DETS.
    persistent? =
      Keyword.get(
        opts,
        :persistent?,
        Application.get_env(:bibtime_station, :buffer_persistent, false)
      )

    table = open_table(persistent?, table_name, opts)
    counter = next_counter(persistent?, table)

    {:ok,
     %{
       table: table,
       table_name: table_name,
       persistent?: persistent?,
       counter: counter
     }}
  end

  @impl true
  def handle_call({:enqueue, read}, _from, state) do
    :ok = insert(state.persistent?, state.table, state.counter, read)
    {:reply, :ok, %{state | counter: state.counter + 1}}
  end

  def handle_call({:drain, count}, _from, state) do
    reads = do_drain(state.persistent?, state.table, count)
    {:reply, reads, state}
  end

  def handle_call(:size, _from, state) do
    {:reply, table_size(state.persistent?, state.table), state}
  end

  def handle_call(:clear, _from, state) do
    :ok = delete_all(state.persistent?, state.table)
    {:reply, :ok, %{state | counter: 0}}
  end

  @impl true
  def terminate(_reason, %{persistent?: persistent?, table: table}) do
    close(persistent?, table)
    :ok
  end

  # ------- table operations -------
  #
  # Each backend (DETS, ETS) has its own clause for every helper, kept
  # adjacent so the compiler is happy. The first arg is `persistent?`
  # — true → DETS, false → ETS.

  defp open_table(true, _name, opts) do
    path =
      Keyword.get(
        opts,
        :dets_path,
        Application.get_env(:bibtime_station, :buffer_path, "/tmp/bibtime_station_buffer.dets")
      )

    _ = File.mkdir_p(Path.dirname(path))

    {:ok, table} =
      :dets.open_file(:bibtime_station_buffer,
        file: String.to_charlist(path),
        type: :set
      )

    table
  end

  defp open_table(false, name, _opts) do
    :ets.new(name, [:ordered_set, :public, :named_table])
  end

  defp next_counter(true, table) do
    case :dets.foldl(fn {k, _}, acc -> max(k, acc) end, -1, table) do
      -1 -> 0
      n -> n + 1
    end
  end

  defp next_counter(false, table) do
    case :ets.last(table) do
      :"$end_of_table" -> 0
      n when is_integer(n) -> n + 1
    end
  end

  defp insert(true, table, key, read), do: :dets.insert(table, {key, read})

  defp insert(false, table, key, read) do
    true = :ets.insert(table, {key, read})
    :ok
  end

  defp do_drain(true, table, count) do
    keys =
      :dets.foldl(fn {k, _v}, acc -> [k | acc] end, [], table)
      |> Enum.sort()
      |> Enum.take(count)

    Enum.map(keys, fn k ->
      [{^k, v}] = :dets.lookup(table, k)
      :ok = :dets.delete(table, k)
      v
    end)
  end

  defp do_drain(false, table, count) do
    collect_drain(table, :ets.first(table), count, [])
  end

  defp collect_drain(_table, :"$end_of_table", _remaining, acc), do: Enum.reverse(acc)
  defp collect_drain(_table, _key, 0, acc), do: Enum.reverse(acc)

  defp collect_drain(table, key, remaining, acc) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        next = :ets.next(table, key)
        :ets.delete(table, key)
        collect_drain(table, next, remaining - 1, [value | acc])

      [] ->
        Enum.reverse(acc)
    end
  end

  defp table_size(true, table), do: :dets.info(table, :size) || 0
  defp table_size(false, table), do: :ets.info(table, :size) || 0

  defp delete_all(true, table) do
    :ok = :dets.delete_all_objects(table)
    :ok
  end

  defp delete_all(false, table) do
    true = :ets.delete_all_objects(table)
    :ok
  end

  defp close(true, table), do: :dets.close(table)
  defp close(false, _table), do: :ok
end
