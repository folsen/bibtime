defmodule Bibtime.Timing.StationSplitAssignment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "station_split_assignments" do
    belongs_to :station, Bibtime.Timing.TimingStation, foreign_key: :station_id
    belongs_to :split, Bibtime.Races.Split

    timestamps()
  end

  @doc false
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:station_id, :split_id])
    |> validate_required([:station_id, :split_id])
    |> unique_constraint(:split_id)
    |> unique_constraint([:station_id, :split_id])
  end
end
