defmodule Bibtime.Repo.Migrations.CreateStationSplitAssignments do
  use Ecto.Migration

  # Stations can now cover multiple splits (e.g. one reader at "bike start"
  # and "bike exit"), so the single assigned_split_id FK moves to a join
  # table. SQLite can't DROP an indexed/FK column, so timing_stations is
  # rebuilt. The rename happens before the join table exists so SQLite's
  # RENAME doesn't rewrite any FK references.
  def up do
    # SQLite keeps index names on rename, so both indexes must go before the
    # new table can claim them.
    drop index(:timing_stations, [:assigned_split_id])
    drop index(:timing_stations, [:token])
    rename table(:timing_stations), to: table(:timing_stations_old)

    create table(:timing_stations) do
      add :name, :string, null: false
      add :token, :string, null: false
      add :status, :string, null: false, default: "offline"
      add :last_seen_at, :utc_datetime
      add :firmware_version, :string
      add :metadata, :map, null: false, default: %{}
      add :pass_lockout_seconds, :integer, null: false, default: 120

      timestamps()
    end

    execute """
    INSERT INTO timing_stations
      (id, name, token, status, last_seen_at, firmware_version, metadata,
       pass_lockout_seconds, inserted_at, updated_at)
    SELECT id, name, token, status, last_seen_at, firmware_version, metadata,
           120, inserted_at, updated_at
    FROM timing_stations_old
    """

    create unique_index(:timing_stations, [:token])

    create table(:station_split_assignments) do
      add :station_id, references(:timing_stations, on_delete: :delete_all), null: false
      add :split_id, references(:splits, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:station_split_assignments, [:split_id])
    create unique_index(:station_split_assignments, [:station_id, :split_id])

    execute """
    INSERT INTO station_split_assignments (station_id, split_id, inserted_at, updated_at)
    SELECT id, assigned_split_id, datetime('now'), datetime('now')
    FROM timing_stations_old
    WHERE assigned_split_id IS NOT NULL
    """

    drop table(:timing_stations_old)
  end

  # Multi-split assignments collapse to the lowest-sort_order split.
  def down do
    alter table(:timing_stations) do
      add :assigned_split_id, references(:splits, on_delete: :nilify_all)
    end

    execute """
    UPDATE timing_stations
    SET assigned_split_id = (
      SELECT ssa.split_id
      FROM station_split_assignments ssa
      JOIN splits s ON s.id = ssa.split_id
      WHERE ssa.station_id = timing_stations.id
      ORDER BY s.sort_order ASC, s.id ASC
      LIMIT 1
    )
    """

    create unique_index(:timing_stations, [:assigned_split_id],
             where: "assigned_split_id IS NOT NULL"
           )

    drop table(:station_split_assignments)

    alter table(:timing_stations) do
      remove :pass_lockout_seconds
    end
  end
end
