defmodule Bibtime.Participants.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "participants" do
    field :bib_number, :string
    field :first_name, :string
    field :last_name, :string
    # Email is collected on the registration form to find/create the linked
    # user, but never persisted on the participant — the user record is the
    # single source of truth. See Registration.register_participant/2.
    field :email, :string, virtual: true
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
      # Virtual — used by the admin form so the email roundtrips through
      # phx-change. Persistence is via the linked user, not this field;
      # `Participants.create_participant/1` extracts it before insert.
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
    # Keep this in lockstep with Accounts.User's email validation so that any
    # address accepted here can also become a user account — the email is
    # used to find-or-create the linked user. A stricter form here would let
    # an address through registration that user creation then rejects,
    # silently leaving the participant with no user and no way to reach them.
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 160)
  end

  @doc """
  Changeset for the public "edit my registration" form.

  Deliberately narrow: it casts only the display fields a participant may
  change about themselves. It must never cast `:status`, `:bib_number`,
  `:chip_id`, `:race_id`, `:hold_expires_at`, `:checked_in_at`, or
  `:registration_data` — those are timing/admin-controlled, and letting an
  end user set them via a crafted form submission would be a
  privilege-escalation / data-integrity hole. Email is excluded too: it
  lives on the linked user account.
  """
  def self_edit_changeset(participant, attrs, opts \\ []) do
    required =
      if Keyword.get(opts, :require_category, false),
        do: [:first_name, :race_category_id],
        else: [:first_name]

    participant
    |> cast(attrs, [:first_name, :last_name, :gender, :birth_date, :club, :race_category_id])
    |> validate_required(required)
  end
end
