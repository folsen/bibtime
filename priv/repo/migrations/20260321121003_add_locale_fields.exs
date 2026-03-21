defmodule Bibtime.Repo.Migrations.AddLocaleFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferred_locale, :string, default: nil
    end

    alter table(:races) do
      add :default_locale, :string, default: nil
    end
  end
end
