defmodule Bibtime.Repo.Migrations.AddPhotosPublicToRaces do
  use Ecto.Migration

  def change do
    alter table(:races) do
      add :photos_public, :boolean, default: true, null: false
    end
  end
end
