defmodule Bibtime.Participants.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "participants" do
    field :bib_number, :string
    field :first_name, :string
    field :last_name, :string
    field :email, :string
    field :birth_date, :date
    field :gender, Ecto.Enum, values: [:male, :female, :other]
    field :club, :string
    field :chip_id, :string

    field :status, Ecto.Enum,
      values: [:registered, :racing, :dns, :dnf, :dsq, :finished],
      default: :registered

    field :registration_data, :map, default: %{}
    field :confirmation_token, :string

    belongs_to :race, Bibtime.Races.Race
    belongs_to :race_category, Bibtime.Races.RaceCategory
    belongs_to :user, Bibtime.Accounts.User

    has_many :split_times, Bibtime.Timing.SplitTime

    timestamps()
  end

  @doc false
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :bib_number,
      :first_name,
      :last_name,
      :email,
      :birth_date,
      :gender,
      :club,
      :chip_id,
      :status,
      :registration_data,
      :race_id,
      :race_category_id
    ])
    |> validate_required([:bib_number, :first_name, :last_name, :race_id])
    |> unique_constraint([:race_id, :bib_number])
  end

  def registration_changeset(participant, attrs) do
    participant
    |> cast(attrs, [
      :first_name,
      :last_name,
      :email,
      :birth_date,
      :gender,
      :club,
      :race_category_id
    ])
    |> validate_required([:first_name, :last_name, :email, :race_category_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
  end
end
