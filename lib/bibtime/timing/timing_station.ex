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
    field :pass_lockout_seconds, :integer, default: 120

    has_many :split_assignments, Bibtime.Timing.StationSplitAssignment, foreign_key: :station_id

    has_many :assigned_splits, through: [:split_assignments, :split]

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
      :pass_lockout_seconds
    ])
    |> validate_required([:name, :token])
    |> validate_number(:pass_lockout_seconds, greater_than_or_equal_to: 0)
    |> unique_constraint(:token)
  end
end
