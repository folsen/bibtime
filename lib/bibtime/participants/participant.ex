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
    field :checked_in_at, :utc_datetime
    field :hold_expires_at, :utc_datetime

    field :status, Ecto.Enum,
      values: [:pending_payment, :registered, :checked_in, :racing, :dns, :dnf, :dsq, :finished],
      default: :registered

    field :registration_data, :map, default: %{}
    field :confirmation_token, :string

    belongs_to :race, Bibtime.Races.Race
    belongs_to :race_category, Bibtime.Races.RaceCategory
    belongs_to :user, Bibtime.Accounts.User

    has_many :split_times, Bibtime.Timing.SplitTime
    has_many :payments, Bibtime.Payments.Payment

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
      :checked_in_at,
      :hold_expires_at,
      :status,
      :registration_data,
      :race_id,
      :race_category_id
    ])
    |> validate_required([:first_name, :race_id])
    |> require_bib_when_not_pending()
    |> unique_constraint([:race_id, :bib_number])
  end

  # Bib numbers are only assigned when a participant becomes :registered
  # (or any later racing state). Pending-payment rows are allowed to have
  # a nil bib — the hold reserves the slot, the bib is assigned at payment.
  defp require_bib_when_not_pending(changeset) do
    case get_field(changeset, :status) do
      :pending_payment -> changeset
      nil -> changeset
      _ -> validate_required(changeset, [:bib_number])
    end
  end

  def registration_changeset(participant, attrs, opts \\ []) do
    required = [:first_name, :email]

    required =
      if Keyword.get(opts, :require_category, true),
        do: required ++ [:race_category_id],
        else: required

    required =
      if Keyword.get(opts, :require_gender, false), do: required ++ [:gender], else: required

    required =
      if Keyword.get(opts, :require_birth_date, false),
        do: required ++ [:birth_date],
        else: required

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
    |> validate_required(required)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
  end
end
