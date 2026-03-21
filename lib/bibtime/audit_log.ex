defmodule Bibtime.AuditLog do
  @moduledoc """
  Context for tracking admin actions.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo
  alias Bibtime.AuditLog.AuditLogEntry

  @doc """
  Logs an admin action.
  """
  def log(user, action, resource_type, resource_id \\ nil, metadata \\ %{})

  def log(%{id: user_id}, action, resource_type, resource_id, metadata) do
    %AuditLogEntry{}
    |> AuditLogEntry.changeset(%{
      user_id: user_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    })
    |> Repo.insert()
  end

  def log(nil, action, resource_type, resource_id, metadata) do
    %AuditLogEntry{}
    |> AuditLogEntry.changeset(%{
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Lists audit log entries, most recent first.
  """
  def list_entries(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLogEntry
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:user)
    |> Repo.all()
  end
end
