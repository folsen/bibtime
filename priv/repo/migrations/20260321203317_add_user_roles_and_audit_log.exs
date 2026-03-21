defmodule Bibtime.Repo.Migrations.AddUserRolesAndAuditLog do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
    end

    execute("UPDATE users SET role = 'admin' WHERE is_admin = 1")

    create table(:audit_logs) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:resource_type, :resource_id])
    create index(:audit_logs, [:inserted_at])
  end

  def down do
    drop table(:audit_logs)

    alter table(:users) do
      remove :role
    end
  end
end
