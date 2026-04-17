defmodule Bibtime.SiteSettings.SiteSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @cta_modes ~w(default featured_race custom)
  @supported_locales ~w(en sv)

  schema "site_settings" do
    field :site_name, :string, default: "BibTime"

    field :hero_title, :map, default: %{}
    field :hero_subtitle, :map, default: %{}
    field :cta_label, :map, default: %{}

    field :cta_mode, :string, default: "default"
    field :cta_url, :string

    field :default_locale, :string, default: "en"

    field :organizer_email, :string
    field :organizer_website, :string

    belongs_to :featured_race, Bibtime.Races.Race

    timestamps()
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :site_name,
      :hero_title,
      :hero_subtitle,
      :cta_label,
      :cta_mode,
      :cta_url,
      :default_locale,
      :featured_race_id,
      :organizer_email,
      :organizer_website
    ])
    |> validate_required([:site_name, :cta_mode, :default_locale])
    |> validate_length(:site_name, min: 1, max: 60)
    |> validate_inclusion(:cta_mode, @cta_modes)
    |> validate_inclusion(:default_locale, @supported_locales)
    |> normalize_translations(:hero_title)
    |> normalize_translations(:hero_subtitle)
    |> normalize_translations(:cta_label)
    |> validate_cta_fields()
    |> validate_url(:cta_url)
    |> validate_url(:organizer_website)
    |> validate_email(:organizer_email)
  end

  def cta_modes, do: @cta_modes
  def supported_locales, do: @supported_locales

  defp normalize_translations(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value when is_map(value) ->
        cleaned =
          value
          |> Enum.filter(fn {k, v} ->
            k in @supported_locales and is_binary(v) and String.trim(v) != ""
          end)
          |> Enum.map(fn {k, v} -> {k, String.trim(v)} end)
          |> Map.new()

        put_change(changeset, field, cleaned)

      _ ->
        add_error(changeset, field, "must be a map of locale -> string")
    end
  end

  defp validate_cta_fields(changeset) do
    case get_field(changeset, :cta_mode) do
      "featured_race" ->
        if get_field(changeset, :featured_race_id) do
          changeset
        else
          add_error(changeset, :featured_race_id, "is required when CTA mode is Featured race")
        end

      "custom" ->
        if get_field(changeset, :cta_url) do
          changeset
        else
          add_error(changeset, :cta_url, "is required when CTA mode is Custom")
        end

      _ ->
        changeset
    end
  end

  defp validate_url(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      "" ->
        put_change(changeset, field, nil)

      value ->
        cond do
          String.starts_with?(value, "http://") ->
            changeset

          String.starts_with?(value, "https://") ->
            changeset

          String.starts_with?(value, "/") ->
            changeset

          true ->
            add_error(changeset, field, "must start with http://, https://, or /")
        end
    end
  end

  defp validate_email(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      "" ->
        put_change(changeset, field, nil)

      value ->
        if String.contains?(value, "@") and String.contains?(value, ".") do
          changeset
        else
          add_error(changeset, field, "must be a valid email address")
        end
    end
  end
end
