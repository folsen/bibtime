defmodule Bibtime.PaymentsFixtures do
  @moduledoc """
  Test helpers for creating payment entities.
  """

  alias Bibtime.Payments.Payment
  alias Bibtime.Repo

  def payment_fixture(participant, race, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        participant_id: participant.id,
        race_id: race.id,
        stripe_checkout_session_id: "cs_test_#{System.unique_integer([:positive])}",
        amount_cents: 50000,
        currency: "SEK",
        status: :pending
      })

    Repo.insert!(struct(Payment, attrs))
  end
end
