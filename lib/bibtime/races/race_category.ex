defmodule Bibtime.Races.RaceCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "race_categories" do
    field :name, :string
    field :distance_label, :string
    field :gender, Ecto.Enum, values: [:any, :male, :female], default: :any
    field :min_age, :integer
    field :max_age, :integer
    field :sort_order, :integer, default: 0

    belongs_to :race, Bibtime.Races.Race
    has_many :participants, Bibtime.Participants.Participant

    timestamps()
  end

  @doc false
  def changeset(race_category, attrs) do
    race_category
    |> cast(attrs, [:name, :distance_label, :gender, :min_age, :max_age, :sort_order, :race_id])
    |> validate_required([:name, :race_id])
  end
end
