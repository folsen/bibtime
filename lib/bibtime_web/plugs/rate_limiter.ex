defmodule BibtimeWeb.Plugs.RateLimiter do
  @moduledoc """
  Plug that rate-limits POST requests to prevent brute-force login attacks.

  Allows a maximum of 5 login attempts per 15-minute window per IP address.
  Non-POST requests pass through unaffected.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  use Gettext, backend: BibtimeWeb.Gettext

  @max_attempts 5
  @window_seconds 15 * 60

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Bibtime.RateLimiter.check_rate({:login, ip}, @max_attempts, @window_seconds) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, gettext("Too many login attempts. Please try again later."))
        |> redirect(to: "/users/log-in")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
