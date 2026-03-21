defmodule Bibtime.Races.Race do
  use Ecto.Schema
  import Ecto.Changeset

  schema "races" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :date, :date
    field :location, :string
    field :race_type, Ecto.Enum, values: [:triathlon, :running, :cycling, :swimming, :custom]

    field :status, Ecto.Enum,
      values: [
        :draft,
        :registration_open,
        :registration_closed,
        :in_progress,
        :finished,
        :archived
      ]

    field :config, :map, default: %{}

    has_many :categories, Bibtime.Races.RaceCategory
    has_many :auto_categories, Bibtime.Races.RaceAutoCategory
    has_many :splits, Bibtime.Races.Split
    has_many :participants, Bibtime.Participants.Participant
    has_many :race_starts, Bibtime.Timing.RaceStart

    timestamps()
  end

  @doc false
  def changeset(race, attrs) do
    race
    |> cast(attrs, [:name, :slug, :description, :date, :location, :race_type, :status, :config])
    |> validate_required([:name, :slug, :race_type, :status])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric and hyphens only"
    )
    |> unique_constraint(:slug)
  end
end
