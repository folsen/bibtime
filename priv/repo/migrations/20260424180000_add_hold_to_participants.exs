defmodule Bibtime.Repo.Migrations.AddHoldToParticipants do
  use Ecto.Migration

  @moduledoc """
  Shifts bib-number assignment from registration time to payment time for
  paid races. Pending participants instead hold a race slot that expires
  after a TTL; capacity is computed from `status = :registered` plus
  non-expired holds rather than by raw participant count.

  Changes:
    * adds `hold_expires_at :utc_datetime`
    * relaxes `bib_number NOT NULL` (SQLite writable_schema trick)
    * replaces the `(race_id, bib_number)` unique index with a partial
      index that only applies when `bib_number IS NOT NULL`
    * backfills existing `pending_payment` rows with a far-future hold so
      their bibs remain grandfathered and they still count toward capacity
  """

  def up do
    alter table(:participants) do
      add :hold_expires_at, :utc_datetime
    end

    rewrite_bib_number_ddl(
      ~s{"bib_number" TEXT NOT NULL},
      ~s{"bib_number" TEXT}
    )

    drop unique_index(:participants, [:race_id, :bib_number])

    execute """
    CREATE UNIQUE INDEX participants_race_id_bib_number_index
    ON participants (race_id, bib_number)
    WHERE bib_number IS NOT NULL
    """

    execute """
    UPDATE participants
    SET hold_expires_at = '2099-01-01T00:00:00'
    WHERE status = 'pending_payment'
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS participants_race_id_bib_number_index"
    create unique_index(:participants, [:race_id, :bib_number])

    rewrite_bib_number_ddl(
      ~s{"bib_number" TEXT,},
      ~s{"bib_number" TEXT NOT NULL,}
    )

    alter table(:participants) do
      remove :hold_expires_at
    end
  end

  defp rewrite_bib_number_ddl(from, to) do
    execute("PRAGMA writable_schema=ON")

    execute("""
    UPDATE sqlite_master
       SET sql = replace(sql, '#{from}', '#{to}')
     WHERE type = 'table' AND name = 'participants'
    """)

    repo().query!("PRAGMA schema_version")
    |> Map.fetch!(:rows)
    |> List.first()
    |> List.first()
    |> then(&execute("PRAGMA schema_version = #{&1 + 1}"))

    execute("PRAGMA writable_schema=OFF")
    execute("PRAGMA integrity_check")
  end
end
