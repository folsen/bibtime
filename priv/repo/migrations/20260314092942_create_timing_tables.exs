defmodule Bibtime.Repo.Migrations.CreateTimingTables do
  use Ecto.Migration

  def change do
    create table(:race_starts) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :race_category_id, references(:race_categories, on_delete: :nilify_all)
      add :started_at, :utc_datetime_usec, null: false
      add :wave_name, :string

      timestamps()
    end

    create index(:race_starts, [:race_id])

    create table(:split_times) do
      add :participant_id, references(:participants, on_delete: :delete_all), null: false
      add :split_id, references(:splits, on_delete: :delete_all), null: false
      add :absolute_time, :utc_datetime_usec
      add :elapsed_ms, :integer, null: false
      add :source, :string, null: false, default: "manual"
      add :raw_chip_data, :string

      timestamps(updated_at: false)
    end

    create unique_index(:split_times, [:participant_id, :split_id])
    create index(:split_times, [:split_id])
  end
end
