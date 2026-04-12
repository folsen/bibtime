defmodule BibtimeWeb.API.StationAuth do
  @moduledoc """
  Looks up a `Bibtime.Timing.TimingStation` by the `:token` path param and
  assigns it to `conn.assigns.station`. If the token is missing or invalid,
  halts the connection with a 401 JSON response.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Bibtime.Timing

  def init(opts), do: opts

  def call(conn, _opts) do
    token = conn.path_params["token"] || conn.params["token"]

    case Timing.get_station_by_token(token) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "error", reason: "invalid_token"})
        |> halt()

      station ->
        assign(conn, :station, station)
    end
  end
end
