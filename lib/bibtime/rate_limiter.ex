defmodule Bibtime.RateLimiter do
  @moduledoc """
  ETS-backed rate limiter using windowed buckets.

  Tracks request counts per key within time windows. Used to prevent
  brute-force attacks on authentication endpoints.
  """
  use GenServer

  @table :rate_limiter
  @cleanup_interval :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Increment the counter for `key` and check if the rate limit is exceeded.

  Returns `:ok` if under the limit, `{:error, :rate_limited}` if exceeded.

  The window is divided into fixed buckets of `window_seconds` duration.
  Counters reset at the start of each new window.
  """
  def check_rate(key, max_attempts, window_seconds) do
    now = System.system_time(:second)
    bucket = div(now, window_seconds)
    full_key = {key, bucket}
    expires_at = (bucket + 1) * window_seconds

    count = :ets.update_counter(@table, full_key, {2, 1}, {full_key, 0, expires_at})

    if count > max_attempts do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  @doc """
  Clear all rate limit entries. Used in tests.
  """
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)

    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
