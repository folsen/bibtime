defmodule BibtimeWeb.Plugs.SetLocale do
  @moduledoc """
  Plug that sets the Gettext locale based on (in priority order):
  1. `locale` query parameter
  2. Session preference
  3. Logged-in user's preferred_locale
  4. Accept-Language header
  5. Default locale ("en")
  """

  import Plug.Conn

  @supported_locales ~w(en sv)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      locale_from_params(conn) ||
        locale_from_session(conn) ||
        locale_from_user(conn) ||
        locale_from_header(conn) ||
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

  defp locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(fn part ->
      part = String.trim(part)

      {lang, quality} =
        case String.split(part, ";q=") do
          [lang, q] ->
            case Float.parse(q) do
              {quality, _} -> {lang, quality}
              :error -> {lang, 1.0}
            end

          [lang] ->
            {lang, 1.0}
        end

      lang = lang |> String.split("-") |> List.first() |> String.downcase()
      {lang, quality}
    end)
    |> Enum.sort_by(fn {_lang, q} -> q end, :desc)
    |> Enum.find_value(fn {lang, _q} ->
      if lang in @supported_locales, do: lang
    end)
  end

  defp default_locale, do: "en"

  def supported_locales, do: @supported_locales
end
