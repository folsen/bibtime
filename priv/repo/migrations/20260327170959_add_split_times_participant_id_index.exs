defmodule Bibtime.Repo.Migrations.AddSplitTimesParticipantIdIndex do
  use Ecto.Migration

  def change do
    create index(:split_times, [:participant_id])
  end
end
