defmodule Bibtime.Repo.Migrations.AddDefaultLocaleToSiteSettings do
  use Ecto.Migration

  def change do
    alter table(:site_settings) do
      add :default_locale, :string, null: false, default: "en"
    end
  end
end
