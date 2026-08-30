defmodule Bibtime.Repo.Migrations.AddPhotoUploadsEnabledToRaces do
  use Ecto.Migration

  def change do
    alter table(:races) do
      add :photo_uploads_enabled, :boolean, default: true, null: false
    end
  end
end
