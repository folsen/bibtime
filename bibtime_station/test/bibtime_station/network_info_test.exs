defmodule BibtimeStation.NetworkInfoTest do
  use ExUnit.Case, async: false

  alias BibtimeStation.NetworkInfo

  setup do
    NetworkInfo.clear_cache()
    on_exit(fn -> NetworkInfo.clear_cache() end)
  end

  test "info/0 returns the three reporting fields" do
    info = NetworkInfo.info()

    assert Map.has_key?(info, :local_ip)
    assert Map.has_key?(info, :tailscale_ip)
    assert Map.has_key?(info, :tailscale_status)

    assert is_nil(info.local_ip) or is_binary(info.local_ip)
    assert is_nil(info.tailscale_ip) or is_binary(info.tailscale_ip)
    assert info.tailscale_status in ["online", "offline", "not_installed"]
  end

  test "info/0 caches between calls" do
    first = NetworkInfo.info()
    assert NetworkInfo.info() == first
  end
end
