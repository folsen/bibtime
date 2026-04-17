defmodule BibtimeWeb.Plugs.SetLocale do
  @moduledoc """
  Plug that sets the Gettext locale based on (in priority order):
  1. `locale` query parameter
  2. Session preference
  3. Logged-in user's preferred_locale
  4. Site-wide default (configured in admin Site Settings)
  """

  import Plug.Conn

  @supported_locales ~w(en sv)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      locale_from_params(conn) ||
        locale_from_session(conn) ||
        locale_from_user(conn) ||
        default_locale()

    Gettext.put_locale(BibtimeWeb.Gettext, locale)
    put_session(conn, :locale, locale)
  end

  defp locale_from_params(conn) do
    case conn.params["locale"] do
      locale when locale in @supported_locales -> locale
      _ -> nil
    end
  end

  defp locale_from_session(conn) do
    case get_session(conn, :locale) do
      locale when locale in @supported_locales -> locale
      _ -> nil
    end
  end

  defp locale_from_user(conn) do
    case conn.assigns do
      %{current_scope: %{user: %{preferred_locale: locale}}} when locale in @supported_locales ->
        locale

      _ ->
        nil
    end
  end

  defp default_locale do
    case Bibtime.SiteSettings.get().default_locale do
      locale when locale in @supported_locales -> locale
      _ -> "en"
    end
  end

  def supported_locales, do: @supported_locales
end
