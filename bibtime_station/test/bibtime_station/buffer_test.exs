defmodule BibtimeStation.BufferTest do
  use ExUnit.Case, async: false

  alias BibtimeStation.Buffer

  setup do
    # Use a unique table name per test to avoid collisions across runs.
    table_name = :"buffer_test_#{System.unique_integer([:positive])}"
    name = :"buffer_#{System.unique_integer([:positive])}"

    {:ok, _pid} = Buffer.start_link(name: name, table_name: table_name)

    # The Buffer uses @name module-level. Tests call the public API
    # through the registered-under-@name server, which we've just
    # started under a different name — so skip the public API and hit
    # the GenServer directly.
    %{server: name}
  end

  test "enqueue/drain/size", %{server: server} do
    assert GenServer.call(server, :size) == 0

    :ok = GenServer.call(server, {:enqueue, %{chip_id: "A"}})
    :ok = GenServer.call(server, {:enqueue, %{chip_id: "B"}})
    :ok = GenServer.call(server, {:enqueue, %{chip_id: "C"}})

    assert GenServer.call(server, :size) == 3

    drained = GenServer.call(server, {:drain, 2})
    assert drained == [%{chip_id: "A"}, %{chip_id: "B"}]
    assert GenServer.call(server, :size) == 1

    assert GenServer.call(server, {:drain, 10}) == [%{chip_id: "C"}]
    assert GenServer.call(server, :size) == 0
  end

  test "draining an empty buffer returns []", %{server: server} do
    assert GenServer.call(server, {:drain, 5}) == []
  end
end
