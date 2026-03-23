defmodule BibtimeWeb.CacheBodyReader do
  @moduledoc """
  Caches the raw request body for routes that need it (e.g., Stripe webhooks).
  Used as the body_reader option for Plug.Parsers.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    conn =
      if String.starts_with?(conn.request_path, "/webhooks/stripe") do
        Plug.Conn.assign(conn, :raw_body, body)
      else
        conn
      end

    {:ok, body, conn}
  end
end
