defmodule Bibtime.Timing.RaceStart do
  use Ecto.Schema
  import Ecto.Changeset

  schema "race_starts" do
    field :started_at, :utc_datetime_usec
    field :wave_name, :string

    belongs_to :race, Bibtime.Races.Race
    belongs_to :race_category, Bibtime.Races.RaceCategory

    timestamps()
  end

  @doc false
  def changeset(race_start, attrs) do
    race_start
    |> cast(attrs, [:started_at, :wave_name, :race_id, :race_category_id])
    |> validate_required([:started_at, :race_id])
  end
end
