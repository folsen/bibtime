defmodule BibtimeWeb.PageController do
  use BibtimeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
