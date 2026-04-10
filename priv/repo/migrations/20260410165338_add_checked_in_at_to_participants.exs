defmodule Bibtime.Repo.Migrations.AddCheckedInAtToParticipants do
  use Ecto.Migration

  def change do
    alter table(:participants) do
      add :checked_in_at, :utc_datetime
    end
  end
end
