defmodule Bibtime.AuditLog.AuditLogEntry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :integer
    field :metadata, :map, default: %{}

    belongs_to :user, Bibtime.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:action, :resource_type, :resource_id, :metadata, :user_id])
    |> validate_required([:action, :resource_type])
  end
end
