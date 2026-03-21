defmodule BibtimeWeb.LocaleController do
  use BibtimeWeb, :controller

  alias Bibtime.Accounts

  def update(conn, %{"locale" => locale}) do
    supported = BibtimeWeb.Plugs.SetLocale.supported_locales()

    if locale in supported do
      conn = put_session(conn, :locale, locale)

      # If user is logged in, persist their preference
      conn =
        if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
          user = conn.assigns.current_scope.user
          Accounts.update_user_locale(user, locale)
          conn
        else
          conn
        end

      redirect_back(conn)
    else
      redirect_back(conn)
    end
  end

  defp redirect_back(conn) do
    referer =
      conn
      |> get_req_header("referer")
      |> List.first()

    redirect(conn, to: referer_to_path(referer) || "/")
  end

  defp referer_to_path(nil), do: nil

  defp referer_to_path(referer) do
    uri = URI.parse(referer)
    path = uri.path || "/"

    if uri.query do
      "#{path}?#{uri.query}"
    else
      path
    end
  end
end
