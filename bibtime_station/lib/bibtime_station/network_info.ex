defmodule BibtimeStation.NetworkInfo do
  @moduledoc """
  Resolves the station's local IP and Tailscale tunnel state for
  heartbeat reporting.

  Results are cached for 30 seconds: the heartbeat ticks every 10 s and
  neither value changes often enough to justify shelling out to
  `tailscale` on every tick.

  Reported fields:

    * `local_ip` — first non-loopback IPv4, preferring `wlan*`, then
      `usb*`/`wwan*` (4G modems), then wired interfaces. The Tailscale
      interface is excluded; that address is reported separately.
    * `tailscale_ip` — the device's IPv4 on the tailnet, or `nil`.
    * `tailscale_status` — `"online"`, `"offline"`, or `"not_installed"`.
  """

  @cache_key {__MODULE__, :cache}
  @cache_ttl_ms 30_000

  def info do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@cache_key, nil) do
      {cached_at, info} when now - cached_at < @cache_ttl_ms ->
        info

      _ ->
        {tailscale_ip, tailscale_status} = tailscale_info()

        info = %{
          local_ip: local_ip(),
          tailscale_ip: tailscale_ip,
          tailscale_status: tailscale_status
        }

        :persistent_term.put(@cache_key, {now, info})
        info
    end
  end

  @doc false
  def clear_cache, do: :persistent_term.erase(@cache_key)

  # ---- local IP ----

  defp local_ip do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        ifaddrs
        |> Enum.reject(fn {name, _opts} -> skip_interface?(to_string(name)) end)
        |> Enum.flat_map(fn {name, opts} ->
          opts
          |> Keyword.get_values(:addr)
          |> Enum.filter(&ipv4?/1)
          |> Enum.map(&{to_string(name), &1})
        end)
        |> Enum.sort_by(fn {name, _addr} -> interface_priority(name) end)
        |> case do
          [{_name, addr} | _] -> addr |> :inet.ntoa() |> to_string()
          [] -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp skip_interface?("lo" <> _), do: true
  defp skip_interface?("tailscale" <> _), do: true
  defp skip_interface?(_), do: false

  defp ipv4?({127, _, _, _}), do: false
  defp ipv4?({_, _, _, _}), do: true
  defp ipv4?(_), do: false

  defp interface_priority("wlan" <> _), do: 0
  defp interface_priority("usb" <> _), do: 1
  defp interface_priority("wwan" <> _), do: 1
  defp interface_priority("eth" <> _), do: 2
  defp interface_priority(_), do: 3

  # ---- Tailscale ----

  defp tailscale_info do
    case System.cmd("tailscale", ["status", "--json"], stderr_to_stdout: true) do
      {output, 0} ->
        parse_tailscale_status(output)

      {_output, _nonzero} ->
        # Binary exists but the daemon is down or errored.
        {nil, "offline"}
    end
  rescue
    # System.cmd raises when the binary is not on PATH.
    _ -> {nil, "not_installed"}
  end

  defp parse_tailscale_status(json) do
    case Jason.decode(json) do
      {:ok, decoded} ->
        ip =
          decoded
          |> Map.get("Self", %{})
          |> Map.get("TailscaleIPs", [])
          |> Enum.find(fn ip -> is_binary(ip) and String.contains?(ip, ".") end)

        case {decoded["BackendState"], ip} do
          {"Running", ip} when is_binary(ip) -> {ip, "online"}
          _ -> {ip, "offline"}
        end

      {:error, _} ->
        {nil, "offline"}
    end
  end
end
