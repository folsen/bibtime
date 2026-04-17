defmodule BibtimeWeb.PageController do
  use BibtimeWeb, :controller

  alias Bibtime.Races
  alias Bibtime.SiteSettings

  def home(conn, _params) do
    render(conn, :home,
      races: Races.list_races(),
      cta: build_cta(conn.assigns.site_settings)
    )
  end

  defp build_cta(settings) do
    case settings.cta_mode do
      "featured_race" -> featured_race_cta(settings)
      "custom" -> custom_cta(settings)
      _ -> :default
    end
  end

  defp featured_race_cta(settings) do
    case settings.featured_race_id && Races.get_race(settings.featured_race_id) do
      nil ->
        :default

      race ->
        label =
          SiteSettings.localized(settings, :cta_label) ||
            race.name

        url =
          if race.status == :registration_open do
            "/races/#{race.slug}/register"
          else
            "/races/#{race.slug}"
          end

        {:link, label, url}
    end
  end

  defp custom_cta(settings) do
    label = SiteSettings.localized(settings, :cta_label) || settings.site_name
    {:link, label, settings.cta_url}
  end
end
