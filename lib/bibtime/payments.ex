defmodule Bibtime.Payments do
  @moduledoc """
  The Payments context.

  Handles Stripe Checkout integration for paid race registrations,
  payment tracking, and refunds.
  """

  import Ecto.Query
  alias Bibtime.Repo
  alias Bibtime.Payments.Payment
  alias Bibtime.Participants.Participant

  @doc """
  Returns the effective entry fee for a race in cents.
  Uses early bird pricing if applicable (before deadline).
  """
  def effective_fee_cents(race) do
    cond do
      !race.payment_required ->
        0

      race.early_bird_fee_cents && race.early_bird_deadline &&
          Date.compare(Date.utc_today(), race.early_bird_deadline) in [:lt, :eq] ->
        race.early_bird_fee_cents

      true ->
        race.entry_fee_cents
    end
  end

  @doc """
  Creates a Stripe Checkout Session for a participant and stores a pending payment record.
  Returns {:ok, checkout_url} or {:error, reason}.
  """
  def create_checkout_session(participant, race, success_url, cancel_url) do
    stripe_key = Application.get_env(:stripity_stripe, :api_key)

    if is_nil(stripe_key) or stripe_key == "" do
      require Logger
      Logger.error("Stripe API key not configured. Set STRIPE_SECRET_KEY in .env")
      {:error, "Stripe is not configured. Please set STRIPE_SECRET_KEY."}
    else
      do_create_checkout_session(participant, race, success_url, cancel_url)
    end
  end

  defp do_create_checkout_session(participant, race, success_url, cancel_url) do
    amount = effective_fee_cents(race)
    currency = String.downcase(race.currency || "sek")

    participant = Repo.preload(participant, :race_category)

    description =
      case participant.race_category do
        nil -> race.name
        cat -> "#{race.name} - #{cat.name}"
      end

    checkout_params = %{
      mode: "payment",
      success_url: success_url,
      cancel_url: cancel_url,
      line_items: [
        %{
          price_data: %{
            currency: currency,
            unit_amount: amount,
            product_data: %{
              name: race.name,
              description: description
            }
          },
          quantity: 1
        }
      ],
      customer_email: participant.email,
      metadata: %{
        "participant_id" => to_string(participant.id),
        "race_id" => to_string(race.id)
      }
    }

    case Stripe.Checkout.Session.create(checkout_params) do
      {:ok, session} ->
        {:ok, _payment} =
          %Payment{}
          |> Payment.changeset(%{
            participant_id: participant.id,
            race_id: race.id,
            stripe_checkout_session_id: session.id,
            amount_cents: amount,
            currency: String.upcase(currency),
            status: :pending
          })
          |> Repo.insert()

        {:ok, session.url}

      {:error, %Stripe.Error{} = error} ->
        require Logger
        Logger.error("Stripe checkout session creation failed: #{error.message}")
        {:error, error.message}
    end
  end

  @doc """
  Handles a successful checkout session completion from Stripe webhook.
  Marks payment as completed and transitions participant to registered.
  """
  def handle_checkout_completed(session_id) do
    case Repo.one(from p in Payment, where: p.stripe_checkout_session_id == ^session_id) do
      nil ->
        {:error, :payment_not_found}

      %Payment{status: :completed} = payment ->
        {:ok, payment}

      %Payment{} = payment ->
        Repo.transaction(fn ->
          {:ok, payment} =
            payment
            |> Payment.changeset(%{
              status: :completed,
              stripe_payment_intent_id: fetch_payment_intent_id(session_id),
              paid_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.update()

          participant = Repo.get!(Participant, payment.participant_id)

          if participant.status == :pending_payment do
            participant
            |> Ecto.Changeset.change(%{status: :registered})
            |> Repo.update!()
          end

          # Send confirmation email now that payment is complete
          participant = Repo.preload(participant, [:race_category])
          race = Bibtime.Races.get_race!(payment.race_id)

          Bibtime.Registration.RegistrationNotifier.deliver_confirmation(participant, race)
          Bibtime.Payments.PaymentNotifier.deliver_receipt(payment, participant, race)

          payment
        end)
    end
  end

  @doc """
  Checks a pending payment's Stripe session status and fulfills it if paid.
  Called from the confirmation page as a fallback when webhooks are delayed.
  """
  def check_and_fulfill_payment(%Payment{status: :pending} = payment) do
    case Stripe.Checkout.Session.retrieve(payment.stripe_checkout_session_id) do
      {:ok, %{payment_status: "paid"}} ->
        handle_checkout_completed(payment.stripe_checkout_session_id)

      {:ok, _session} ->
        {:ok, payment}

      {:error, _reason} ->
        {:ok, payment}
    end
  end

  def check_and_fulfill_payment(%Payment{} = payment), do: {:ok, payment}
  def check_and_fulfill_payment(nil), do: {:ok, nil}

  defp fetch_payment_intent_id(session_id) do
    case Stripe.Checkout.Session.retrieve(session_id) do
      {:ok, session} -> session.payment_intent
      _ -> nil
    end
  end

  @doc """
  Refunds a payment via Stripe and updates the local record.
  """
  def refund_payment(%Payment{status: :completed} = payment) do
    case payment.stripe_payment_intent_id do
      nil ->
        {:error, "No payment intent ID available for refund"}

      payment_intent_id ->
        case Stripe.Refund.create(%{payment_intent: payment_intent_id}) do
          {:ok, _refund} ->
            payment
            |> Payment.changeset(%{
              status: :refunded,
              refunded_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.update()

          {:error, %Stripe.Error{} = error} ->
            {:error, error.message}
        end
    end
  end

  def refund_payment(%Payment{}), do: {:error, "Can only refund completed payments"}

  @doc """
  Handles a charge.refunded event from Stripe webhook.
  """
  def handle_charge_refunded(payment_intent_id) do
    case Repo.one(from p in Payment, where: p.stripe_payment_intent_id == ^payment_intent_id) do
      nil ->
        {:error, :payment_not_found}

      %Payment{status: :refunded} = payment ->
        {:ok, payment}

      %Payment{} = payment ->
        payment
        |> Payment.changeset(%{
          status: :refunded,
          refunded_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  @doc """
  Gets a payment by ID.
  """
  def get_payment!(id), do: Repo.get!(Payment, id)

  @doc """
  Gets the payment for a participant.
  """
  def get_payment_for_participant(participant_id) do
    Repo.one(
      from p in Payment,
        where: p.participant_id == ^participant_id,
        order_by: [desc: p.inserted_at],
        limit: 1
    )
  end

  @doc """
  Lists all payments for a race, preloading participant.
  """
  def list_payments_for_race(race_id) do
    Repo.all(
      from p in Payment,
        where: p.race_id == ^race_id,
        order_by: [desc: p.inserted_at],
        preload: [:participant]
    )
  end

  @doc """
  Returns payment summary stats for a race.
  """
  def race_payment_summary(race_id) do
    payments =
      Repo.all(from p in Payment, where: p.race_id == ^race_id)

    completed = Enum.filter(payments, &(&1.status == :completed))
    pending = Enum.filter(payments, &(&1.status == :pending))
    refunded = Enum.filter(payments, &(&1.status == :refunded))

    %{
      total_collected_cents: completed |> Enum.map(& &1.amount_cents) |> Enum.sum(),
      total_pending_cents: pending |> Enum.map(& &1.amount_cents) |> Enum.sum(),
      total_refunded_cents: refunded |> Enum.map(& &1.amount_cents) |> Enum.sum(),
      completed_count: length(completed),
      pending_count: length(pending),
      refunded_count: length(refunded),
      currency: List.first(payments) && List.first(payments).currency
    }
  end

  @doc """
  Formats an amount in cents to a display string with currency.
  """
  def format_amount(cents, currency) when is_integer(cents) do
    major = div(cents, 100)
    minor = rem(cents, 100)
    "#{major}.#{String.pad_leading(Integer.to_string(minor), 2, "0")} #{currency}"
  end

  def format_amount(nil, _currency), do: "-"
end
