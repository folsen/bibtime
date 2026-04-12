defmodule Bibtime.Timing.TimingStation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "timing_stations" do
    field :name, :string
    field :token, :string

    field :status, Ecto.Enum,
      values: [:offline, :online, :reading, :error],
      default: :offline

    field :last_seen_at, :utc_datetime
    field :firmware_version, :string
    field :metadata, :map, default: %{}

    belongs_to :assigned_split, Bibtime.Races.Split

    timestamps()
  end

  @doc false
  def changeset(station, attrs) do
    station
    |> cast(attrs, [
      :name,
      :token,
      :status,
      :last_seen_at,
      :firmware_version,
      :metadata,
      :assigned_split_id
    ])
    |> validate_required([:name, :token])
    |> unique_constraint(:token)
    |> unique_constraint(:assigned_split_id)
  end
end
