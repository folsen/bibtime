defmodule Bibtime.Repo.Migrations.RelaxParticipantLastName do
  use Ecto.Migration

  @moduledoc """
  Allows participants.last_name to be NULL. Runners with a single name
  (mononym) and CSV imports missing a surname should not be blocked.

  SQLite does not support ALTER COLUMN, so we patch the stored DDL via
  sqlite_master using `PRAGMA writable_schema`. This preserves all indexes,
  foreign keys, and triggers without requiring a full table rebuild.
  """

  def up do
    rewrite_last_name_ddl(
      ~s{"last_name" TEXT NOT NULL},
      ~s{"last_name" TEXT}
    )
  end

  def down do
    rewrite_last_name_ddl(
      ~s{"last_name" TEXT,},
      ~s{"last_name" TEXT NOT NULL,}
    )
  end

  # Rewrites the stored CREATE TABLE DDL via `PRAGMA writable_schema` and
  # bumps schema_version so existing connections invalidate their cached
  # schema and observe the new NULL constraint on the next statement.
  defp rewrite_last_name_ddl(from, to) do
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
