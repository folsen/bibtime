defmodule Bibtime.SiteSettings do
  @moduledoc """
  Context for whitelabel site-wide settings (singleton).

  A single row in `site_settings` governs the site name, landing-page hero
  copy, call-to-action behaviour, and organizer contact details. The row is
  cached in :persistent_term and refreshed on update.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo
  alias Bibtime.SiteSettings.SiteSettings, as: Settings

  @cache_key {__MODULE__, :current}

  @doc """
  Returns the current site settings, loading from DB on first access and
  caching in :persistent_term. Creates the default row if none exists.
  """
  def get do
    case :persistent_term.get(@cache_key, :miss) do
      :miss ->
        settings = load_or_create()
        :persistent_term.put(@cache_key, settings)
        settings

      settings ->
        settings
    end
  end

  @doc """
  Returns a changeset for the given settings struct.
  """
  def change(settings \\ get(), attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc """
  Updates the singleton settings record and refreshes the cache.
  """
  def update(attrs) do
    result =
      get()
      |> Settings.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, settings} ->
        :persistent_term.put(@cache_key, settings)
        {:ok, settings}

      other ->
        other
    end
  end

  @doc """
  Resolves the locale to use for a given user (or nil). Falls back to the
  site-wide default when the user has no explicit preference.
  """
  def locale_for(%{preferred_locale: locale}) when is_binary(locale) and locale != "",
    do: locale

  def locale_for(_), do: get().default_locale

  @doc """
  Clears the cache. Use in tests after direct DB manipulation.
  """
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  @doc """
  Looks up a translatable field (hero_title, hero_subtitle, cta_label) for the
  given locale. Falls back to the English value, then to nil.
  """
  def localized(%Settings{} = settings, field, locale)
      when field in [:hero_title, :hero_subtitle, :cta_label] do
    map = Map.get(settings, field) || %{}

    case map do
      %{^locale => value} when is_binary(value) and value != "" ->
        value

      _ ->
        case Map.get(map, "en") do
          value when is_binary(value) and value != "" -> value
          _ -> nil
        end
    end
  end

  @doc """
  Shortcut that looks up a translatable field using the current Gettext locale.
  """
  def localized(settings, field) do
    localized(settings, field, Gettext.get_locale(BibtimeWeb.Gettext))
  end

  defp load_or_create do
    case Repo.one(Settings) do
      nil ->
        {:ok, settings} =
          %Settings{}
          |> Settings.changeset(%{site_name: "BibTime", cta_mode: "default"})
          |> Repo.insert()

        settings

      settings ->
        settings
    end
  end
end
