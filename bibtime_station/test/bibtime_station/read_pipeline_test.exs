defmodule BibtimeStation.ReadPipelineTest do
  use ExUnit.Case, async: false

  alias BibtimeStation.ReadPipeline

  defmodule FakeUplink do
    use GenServer

    def start_link(test_pid) do
      GenServer.start_link(__MODULE__, test_pid)
    end

    def init(test_pid), do: {:ok, %{test_pid: test_pid, seen: []}}

    def handle_cast({:send_read, read}, state) do
      send(state.test_pid, {:dispatched, read})
      {:noreply, %{state | seen: [read | state.seen]}}
    end

    def handle_call(:seen, _from, state), do: {:reply, Enum.reverse(state.seen), state}
  end

  setup do
    {:ok, uplink} = FakeUplink.start_link(self())

    # Manually-controlled monotonic clock.
    clock_pid = spawn_link(fn -> clock_loop(0) end)

    clock_fn = fn ->
      ref = make_ref()
      send(clock_pid, {:get, self(), ref})

      receive do
        {^ref, t} -> t
      after
        1000 -> 0
      end
    end

    {:ok, pipeline} =
      ReadPipeline.start_link(
        name: :"pipeline_#{System.unique_integer()}",
        uplink: uplink,
        dedup_window_ms: 5_000,
        clock: clock_fn
      )

    %{pipeline: pipeline, uplink: uplink, clock_pid: clock_pid}
  end

  defp clock_loop(t) do
    receive do
      {:set, new_t} -> clock_loop(new_t)
      {:get, from, ref} ->
        send(from, {ref, t})
        clock_loop(t)
    end
  end

  defp set_clock(clock_pid, t), do: send(clock_pid, {:set, t})

  test "forwards the first read for a new chip_id", %{pipeline: pipeline} do
    GenServer.cast(pipeline, {:tag_read, %{chip_id: "ABC", rssi: 100, read_at: DateTime.utc_now()}})
    assert_receive {:dispatched, %{chip_id: "ABC"}}
    assert ReadPipeline.read_count(pipeline) == 1
  end

  test "100 reads of same chip within window collapse to 1", %{pipeline: pipeline, clock_pid: clock_pid} do
    set_clock(clock_pid, 0)

    for _ <- 1..100 do
      GenServer.cast(pipeline, {:tag_read, %{chip_id: "SAMECHIP", rssi: 120, read_at: DateTime.utc_now()}})
    end

    # Drain all casts by synchronizing on the pipeline.
    _ = ReadPipeline.read_count(pipeline)

    assert_receive {:dispatched, %{chip_id: "SAMECHIP"}}
    refute_receive {:dispatched, %{chip_id: "SAMECHIP"}}, 50
    assert ReadPipeline.read_count(pipeline) == 1
  end

  test "a read at t=0 and another at t=6000 both forward", %{pipeline: pipeline, clock_pid: clock_pid} do
    set_clock(clock_pid, 0)
    GenServer.cast(pipeline, {:tag_read, %{chip_id: "X", rssi: 10, read_at: DateTime.utc_now()}})
    _ = ReadPipeline.read_count(pipeline)
    assert_receive {:dispatched, %{chip_id: "X"}}

    set_clock(clock_pid, 6000)
    GenServer.cast(pipeline, {:tag_read, %{chip_id: "X", rssi: 10, read_at: DateTime.utc_now()}})
    _ = ReadPipeline.read_count(pipeline)
    assert_receive {:dispatched, %{chip_id: "X"}}

    assert ReadPipeline.read_count(pipeline) == 2
  end

  test "different chips are not deduped against each other", %{pipeline: pipeline, clock_pid: clock_pid} do
    set_clock(clock_pid, 0)
    GenServer.cast(pipeline, {:tag_read, %{chip_id: "A", rssi: 10, read_at: DateTime.utc_now()}})
    GenServer.cast(pipeline, {:tag_read, %{chip_id: "B", rssi: 10, read_at: DateTime.utc_now()}})
    _ = ReadPipeline.read_count(pipeline)

    assert_receive {:dispatched, %{chip_id: "A"}}
    assert_receive {:dispatched, %{chip_id: "B"}}
    assert ReadPipeline.read_count(pipeline) == 2
  end
end
