defmodule Bibtime.PaymentsTest do
  use Bibtime.DataCase, async: true

  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PaymentsFixtures

  alias Bibtime.Payments
  alias Bibtime.Payments.Payment

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp paid_race_fixture do
    race_fixture(%{
      payment_required: true,
      entry_fee_cents: 50000,
      currency: "SEK"
    })
  end

  # ---------------------------------------------------------------------------
  # effective_fee_cents/1
  # ---------------------------------------------------------------------------

  describe "effective_fee_cents/1" do
    test "returns 0 when payment is not required" do
      race = race_fixture(%{payment_required: false})
      assert Payments.effective_fee_cents(race) == 0
    end

    test "returns entry_fee_cents when no early bird pricing" do
      race = paid_race_fixture()
      assert Payments.effective_fee_cents(race) == 50000
    end

    test "returns early bird price when before deadline" do
      race =
        race_fixture(%{
          payment_required: true,
          entry_fee_cents: 50000,
          early_bird_fee_cents: 30000,
          early_bird_deadline: Date.add(Date.utc_today(), 7),
          currency: "SEK"
        })

      assert Payments.effective_fee_cents(race) == 30000
    end

    test "returns early bird price on deadline day" do
      race =
        race_fixture(%{
          payment_required: true,
          entry_fee_cents: 50000,
          early_bird_fee_cents: 30000,
          early_bird_deadline: Date.utc_today(),
          currency: "SEK"
        })

      assert Payments.effective_fee_cents(race) == 30000
    end

    test "returns regular price after early bird deadline" do
      race =
        race_fixture(%{
          payment_required: true,
          entry_fee_cents: 50000,
          early_bird_fee_cents: 30000,
          early_bird_deadline: Date.add(Date.utc_today(), -1),
          currency: "SEK"
        })

      assert Payments.effective_fee_cents(race) == 50000
    end

    test "returns regular price when early_bird_fee_cents is nil" do
      race =
        race_fixture(%{
          payment_required: true,
          entry_fee_cents: 50000,
          early_bird_fee_cents: nil,
          early_bird_deadline: Date.add(Date.utc_today(), 7),
          currency: "SEK"
        })

      assert Payments.effective_fee_cents(race) == 50000
    end
  end

  # ---------------------------------------------------------------------------
  # format_amount/2
  # ---------------------------------------------------------------------------

  describe "format_amount/2" do
    test "formats cents to major.minor with currency" do
      assert Payments.format_amount(50000, "SEK") == "500.00 SEK"
    end

    test "formats zero cents" do
      assert Payments.format_amount(0, "EUR") == "0.00 EUR"
    end

    test "pads minor unit" do
      assert Payments.format_amount(1005, "NOK") == "10.05 NOK"
    end

    test "handles single-digit minor" do
      assert Payments.format_amount(101, "SEK") == "1.01 SEK"
    end

    test "returns dash for nil" do
      assert Payments.format_amount(nil, "SEK") == "-"
    end
  end

  # ---------------------------------------------------------------------------
  # Payment record CRUD
  # ---------------------------------------------------------------------------

  describe "get_payment!/1" do
    test "returns payment by id" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})
      payment = payment_fixture(participant, race)

      found = Payments.get_payment!(payment.id)
      assert found.id == payment.id
    end

    test "raises when payment not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_payment!(0)
      end
    end
  end

  describe "get_payment_for_participant/1" do
    test "returns a payment for a participant" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      payment = payment_fixture(participant, race, %{amount_cents: 50000})

      found = Payments.get_payment_for_participant(participant.id)
      assert found.id == payment.id
    end

    test "returns nil when no payment exists" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      assert Payments.get_payment_for_participant(participant.id) == nil
    end
  end

  describe "list_payments_for_race/1" do
    test "returns all payments for a race, most recent first" do
      race = paid_race_fixture()
      p1 = participant_fixture(race, %{bib_number: "1"})
      p2 = participant_fixture(race, %{bib_number: "2"})

      payment_fixture(p1, race, %{amount_cents: 50000})
      payment_fixture(p2, race, %{amount_cents: 50000})

      payments = Payments.list_payments_for_race(race.id)
      assert length(payments) == 2
      # Verify preloads
      assert Enum.all?(payments, fn p -> p.participant != nil end)
    end

    test "does not include payments from other races" do
      race1 = paid_race_fixture()
      race2 = paid_race_fixture()
      p1 = participant_fixture(race1, %{bib_number: "1"})
      p2 = participant_fixture(race2, %{bib_number: "1"})

      payment_fixture(p1, race1)
      payment_fixture(p2, race2)

      assert length(Payments.list_payments_for_race(race1.id)) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # race_payment_summary/1
  # ---------------------------------------------------------------------------

  describe "race_payment_summary/1" do
    test "returns zeroes for a race with no payments" do
      race = paid_race_fixture()
      summary = Payments.race_payment_summary(race.id)

      assert summary.total_collected_cents == 0
      assert summary.total_pending_cents == 0
      assert summary.total_refunded_cents == 0
      assert summary.completed_count == 0
      assert summary.pending_count == 0
      assert summary.refunded_count == 0
      assert summary.currency == nil
    end

    test "aggregates payments by status" do
      race = paid_race_fixture()
      p1 = participant_fixture(race, %{bib_number: "1"})
      p2 = participant_fixture(race, %{bib_number: "2"})
      p3 = participant_fixture(race, %{bib_number: "3"})

      payment_fixture(p1, race, %{status: :completed, amount_cents: 50000})
      payment_fixture(p2, race, %{status: :pending, amount_cents: 50000})
      payment_fixture(p3, race, %{status: :refunded, amount_cents: 30000})

      summary = Payments.race_payment_summary(race.id)

      assert summary.completed_count == 1
      assert summary.total_collected_cents == 50000
      assert summary.pending_count == 1
      assert summary.total_pending_cents == 50000
      assert summary.refunded_count == 1
      assert summary.total_refunded_cents == 30000
      assert summary.currency == "SEK"
    end
  end

  # ---------------------------------------------------------------------------
  # handle_checkout_completed/1
  # ---------------------------------------------------------------------------

  describe "handle_checkout_completed/1" do
    test "returns error for unknown session" do
      assert {:error, :payment_not_found} =
               Payments.handle_checkout_completed("cs_nonexistent")
    end

    test "returns ok for already completed payment" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})
      payment = payment_fixture(participant, race, %{status: :completed})

      assert {:ok, returned} =
               Payments.handle_checkout_completed(payment.stripe_checkout_session_id)

      assert returned.id == payment.id
    end
  end

  # ---------------------------------------------------------------------------
  # handle_charge_refunded/1
  # ---------------------------------------------------------------------------

  describe "handle_charge_refunded/1" do
    test "returns error for unknown payment intent" do
      assert {:error, :payment_not_found} =
               Payments.handle_charge_refunded("pi_nonexistent")
    end

    test "returns ok for already refunded payment" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      payment =
        payment_fixture(participant, race, %{
          status: :refunded,
          stripe_payment_intent_id: "pi_test_123"
        })

      assert {:ok, returned} =
               Payments.handle_charge_refunded("pi_test_123")

      assert returned.id == payment.id
    end

    test "marks a completed payment as refunded" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      _payment =
        payment_fixture(participant, race, %{
          status: :completed,
          stripe_payment_intent_id: "pi_test_456"
        })

      assert {:ok, refunded} = Payments.handle_charge_refunded("pi_test_456")
      assert refunded.status == :refunded
      assert refunded.refunded_at != nil
    end
  end

  # ---------------------------------------------------------------------------
  # refund_payment/1
  # ---------------------------------------------------------------------------

  describe "refund_payment/1" do
    test "rejects refund of non-completed payment" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})
      payment = payment_fixture(participant, race, %{status: :pending})

      assert {:error, "Can only refund completed payments"} =
               Payments.refund_payment(payment)
    end

    test "rejects refund when no payment intent ID" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      payment =
        payment_fixture(participant, race, %{
          status: :completed,
          stripe_payment_intent_id: nil
        })

      assert {:error, "No payment intent ID available for refund"} =
               Payments.refund_payment(payment)
    end
  end

  # ---------------------------------------------------------------------------
  # check_and_fulfill_payment/1
  # ---------------------------------------------------------------------------

  describe "check_and_fulfill_payment/1" do
    test "returns ok for nil" do
      assert {:ok, nil} = Payments.check_and_fulfill_payment(nil)
    end

    test "returns ok for non-pending payment without calling Stripe" do
      race = paid_race_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})
      payment = payment_fixture(participant, race, %{status: :completed})

      assert {:ok, returned} = Payments.check_and_fulfill_payment(payment)
      assert returned.id == payment.id
    end
  end

  # ---------------------------------------------------------------------------
  # Payment changeset validation
  # ---------------------------------------------------------------------------

  describe "Payment changeset" do
    test "requires mandatory fields" do
      changeset = Payment.changeset(%Payment{}, %{})
      errors = errors_on(changeset)
      assert errors[:participant_id]
      assert errors[:race_id]
      assert errors[:amount_cents]
      assert errors[:currency]
    end

    test "validates amount_cents > 0" do
      changeset =
        Payment.changeset(%Payment{}, %{
          participant_id: 1,
          race_id: 1,
          amount_cents: 0,
          currency: "SEK",
          status: :pending
        })

      assert %{amount_cents: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "validates currency inclusion" do
      changeset =
        Payment.changeset(%Payment{}, %{
          participant_id: 1,
          race_id: 1,
          amount_cents: 100,
          currency: "USD",
          status: :pending
        })

      assert %{currency: [_msg]} = errors_on(changeset)
    end
  end
end
