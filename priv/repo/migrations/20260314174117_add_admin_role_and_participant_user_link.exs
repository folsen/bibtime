defmodule Bibtime.Repo.Migrations.AddAdminRoleAndParticipantUserLink do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end

    alter table(:participants) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:participants, [:user_id])
  end
end
