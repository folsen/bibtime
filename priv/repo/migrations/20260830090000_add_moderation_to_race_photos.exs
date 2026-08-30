defmodule Bibtime.Repo.Migrations.AddModerationToRacePhotos do
  use Ecto.Migration

  def change do
    alter table(:race_photos) do
      # Existing rows are organizer uploads and stay visible: SQLite backfills
      # the NOT NULL column with this default.
      add :status, :string, null: false, default: "approved"
      add :uploaded_by_user_id, references(:users, on_delete: :nilify_all)
      add :reviewed_by_user_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
      add :rejection_reason, :string
    end

    create index(:race_photos, [:race_id, :status])
    create index(:race_photos, [:uploaded_by_user_id])
  end
end
