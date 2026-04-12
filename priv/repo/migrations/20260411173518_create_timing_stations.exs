defmodule Bibtime.Repo.Migrations.CreateTimingStations do
  use Ecto.Migration

  def change do
    create table(:timing_stations) do
      add :name, :string, null: false
      add :token, :string, null: false
      add :status, :string, null: false, default: "offline"
      add :last_seen_at, :utc_datetime
      add :firmware_version, :string
      add :metadata, :map, null: false, default: %{}

      add :assigned_split_id, references(:splits, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:timing_stations, [:token])

    create unique_index(:timing_stations, [:assigned_split_id],
             where: "assigned_split_id IS NOT NULL"
           )
  end
end
