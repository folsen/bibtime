defmodule Bibtime.Repo.Migrations.CreateSiteSettings do
  use Ecto.Migration

  def change do
    create table(:site_settings) do
      add :site_name, :string, null: false, default: "BibTime"

      # Translatable fields stored as JSON maps: %{"en" => "...", "sv" => "..."}
      add :hero_title, :map, null: false, default: %{}
      add :hero_subtitle, :map, null: false, default: %{}
      add :cta_label, :map, null: false, default: %{}

      add :cta_mode, :string, null: false, default: "default"
      add :featured_race_id, references(:races, on_delete: :nilify_all)
      add :cta_url, :string

      add :organizer_email, :string
      add :organizer_website, :string

      timestamps()
    end

    create index(:site_settings, [:featured_race_id])
  end
end
