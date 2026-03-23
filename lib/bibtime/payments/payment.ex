defmodule Bibtime.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payments" do
    field :stripe_checkout_session_id, :string
    field :stripe_payment_intent_id, :string
    field :amount_cents, :integer
    field :currency, :string

    field :status, Ecto.Enum,
      values: [:pending, :completed, :refunded, :failed],
      default: :pending

    field :paid_at, :utc_datetime
    field :refunded_at, :utc_datetime

    belongs_to :participant, Bibtime.Participants.Participant
    belongs_to :race, Bibtime.Races.Race

    timestamps()
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :participant_id,
      :race_id,
      :stripe_checkout_session_id,
      :stripe_payment_intent_id,
      :amount_cents,
      :currency,
      :status,
      :paid_at,
      :refunded_at
    ])
    |> validate_required([:participant_id, :race_id, :amount_cents, :currency, :status])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:currency, ~w(SEK EUR NOK DKK))
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:race_id)
    |> unique_constraint(:stripe_checkout_session_id)
  end
end
