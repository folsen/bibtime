defmodule Bibtime.Races.Split do
  use Ecto.Schema
  import Ecto.Changeset

  schema "splits" do
    field :name, :string
    field :short_name, :string
    field :leg_type, Ecto.Enum, values: [:swim, :bike, :run, :transition, :other]
    field :distance_meters, :integer
    field :sort_order, :integer, default: 0

    belongs_to :race, Bibtime.Races.Race
    has_many :split_times, Bibtime.Timing.SplitTime

    timestamps()
  end

  @doc false
  def changeset(split, attrs) do
    split
    |> cast(attrs, [:name, :short_name, :leg_type, :distance_meters, :sort_order, :race_id])
    |> validate_required([:name, :short_name, :leg_type, :race_id])
  end
end
