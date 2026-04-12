defmodule BibtimeStation.UplinkTest do
  use ExUnit.Case, async: false

  alias BibtimeStation.Uplink

  defmodule FakeBuffer do
    @moduledoc false
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def enqueue(read), do: Agent.update(__MODULE__, &(&1 ++ [read]))

    def drain(count) do
      Agent.get_and_update(__MODULE__, fn list ->
        {Enum.take(list, count), Enum.drop(list, count)}
      end)
    end

    def size, do: Agent.get(__MODULE__, &length/1)
  end

  setup do
    Application.put_env(:bibtime_station, :bibtime_url, "http://localhost:9999")
    Application.put_env(:bibtime_station, :station_token, "test-token")

    # Fresh FakeBuffer per test.
    case Process.whereis(FakeBuffer) do
      nil -> :ok
      pid -> Process.exit(pid, :kill)
    end

    # Give the registered name time to be released.
    wait_until(fn -> Process.whereis(FakeBuffer) == nil end)
    {:ok, _} = FakeBuffer.start_link()
    :ok
  end

  defp wait_until(fun, remaining \\ 50) do
    if fun.() do
      :ok
    else
      if remaining > 0 do
        Process.sleep(5)
        wait_until(fun, remaining - 1)
      else
        :ok
      end
    end
  end

  defp start_uplink(client) do
    name = :"uplink_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Uplink.start_link(
        name: name,
        http_client: client,
        buffer: FakeBuffer,
        schedule_flush?: false
      )

    {pid, name}
  end

  test "on successful POST, marks station online" do
    test_pid = self()

    client = fn url, body ->
      send(test_pid, {:posted, url, body})
      :ok
    end

    {_pid, name} = start_uplink(client)

    read = %{chip_id: "ABC", rssi: 100, read_at: DateTime.utc_now()}
    GenServer.cast(name, {:send_read, read})

    assert_receive {:posted, url, body}, 500
    assert String.ends_with?(url, "/api/stations/test-token/reads")
    assert body.chip_id == "ABC"

    assert Uplink.online?(name) == true
    assert FakeBuffer.size() == 0
  end

  test "on POST failure, buffers the read and marks offline" do
    client = fn _url, _body -> {:error, :econnrefused} end
    {_pid, name} = start_uplink(client)

    read = %{chip_id: "XYZ", rssi: 50, read_at: DateTime.utc_now()}
    GenServer.cast(name, {:send_read, read})

    # Synchronize with a call.
    assert Uplink.online?(name) == false
    assert FakeBuffer.size() == 1
  end

  test "flush_now drains buffer via batch endpoint" do
    test_pid = self()

    client = fn url, body ->
      send(test_pid, {:posted, url, body})
      :ok
    end

    {_pid, name} = start_uplink(client)

    FakeBuffer.enqueue(%{chip_id: "A"})
    FakeBuffer.enqueue(%{chip_id: "B"})

    :ok = Uplink.flush(name)

    assert_receive {:posted, url, body}
    assert String.ends_with?(url, "/api/stations/test-token/reads/batch")
    assert %{reads: reads} = body
    assert Enum.map(reads, & &1.chip_id) == ["A", "B"]

    assert FakeBuffer.size() == 0
    assert Uplink.online?(name) == true
  end

  test "failed flush returns reads to buffer and marks offline" do
    client = fn _url, _body -> {:error, :timeout} end
    {_pid, name} = start_uplink(client)

    FakeBuffer.enqueue(%{chip_id: "A"})
    FakeBuffer.enqueue(%{chip_id: "B"})

    :ok = Uplink.flush(name)

    assert FakeBuffer.size() == 2
    assert Uplink.online?(name) == false
  end
end
