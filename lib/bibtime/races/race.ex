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
    field :default_locale, :string

    # Registration limit
    field :participant_limit, :integer

    # Photo visibility: true = public, false = participants-only
    field :photos_public, :boolean, default: true

    # Payment fields
    field :payment_required, :boolean, default: false
    field :entry_fee_cents, :integer
    field :currency, :string, default: "SEK"
    field :early_bird_fee_cents, :integer
    field :early_bird_deadline, :date

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
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :date,
      :location,
      :race_type,
      :status,
      :config,
      :default_locale,
      :participant_limit,
      :photos_public,
      :payment_required,
      :entry_fee_cents,
      :currency,
      :early_bird_fee_cents,
      :early_bird_deadline
    ])
    |> validate_required([:name, :slug, :race_type, :status])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric and hyphens only"
    )
    |> unique_constraint(:slug)
    |> validate_inclusion(:currency, ~w(SEK EUR NOK DKK))
    |> validate_number(:participant_limit, greater_than: 0)
    |> validate_number(:entry_fee_cents, greater_than: 0)
    |> validate_number(:early_bird_fee_cents, greater_than: 0)
    |> validate_payment_fields()
  end

  defp validate_payment_fields(changeset) do
    if get_field(changeset, :payment_required) do
      changeset
      |> validate_required([:entry_fee_cents, :currency])
    else
      changeset
    end
  end
end
