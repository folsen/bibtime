defmodule Bibtime.Repo.Migrations.CreateRacePhotos do
  use Ecto.Migration

  def change do
    create table(:race_photos) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :split_id, references(:splits, on_delete: :nilify_all)
      add :file_path, :string, null: false
      add :original_filename, :string
      add :content_type, :string
      add :file_size, :integer
      add :bib_numbers, :map, default: "[]"
      add :caption, :string
      add :taken_at, :utc_datetime
      add :sort_order, :integer, default: 0

      timestamps()
    end

    create index(:race_photos, [:race_id])
    create index(:race_photos, [:race_id, :inserted_at])
  end
end
