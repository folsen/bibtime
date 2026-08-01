defmodule Bibtime.Repo.Migrations.AddNeedsReviewToSplitTimes do
  use Ecto.Migration

  def change do
    alter table(:split_times) do
      add :needs_review, :boolean, null: false, default: false
    end
  end
end
