defmodule BibtimeWeb.Plugs.AssignSiteSettings do
  @moduledoc """
  Plug that assigns the current site settings to `conn.assigns.site_settings`.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    assign(conn, :site_settings, Bibtime.SiteSettings.get())
  end
end
