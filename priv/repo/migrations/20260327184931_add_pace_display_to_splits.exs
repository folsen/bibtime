defmodule Bibtime.Repo.Migrations.AddPaceDisplayToSplits do
  use Ecto.Migration

  def change do
    alter table(:splits) do
      add :pace_display, :string, default: "none"
    end
  end
end
