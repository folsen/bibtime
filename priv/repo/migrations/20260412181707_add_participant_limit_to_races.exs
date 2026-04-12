defmodule Bibtime.Repo.Migrations.AddParticipantLimitToRaces do
  use Ecto.Migration

  def change do
    alter table(:races) do
      add :participant_limit, :integer
    end
  end
end
