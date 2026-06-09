defmodule Bibtime.Payments do
  @moduledoc """
  The Payments context.

  Handles Stripe Checkout integration for paid race registrations,
  payment tracking, and refunds.
  """

  import Ecto.Query
  alias Bibtime.Repo
  alias Bibtime.Participants
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
    participant = Repo.preload(participant, [:race_category, :user])

    existing = get_pending_payment_for_participant(participant.id)

    case reusable_session_url(existing) do
      {:ok, url} ->
        {:ok, url}

      :none ->
        checkout_params =
          build_checkout_params(participant, race, amount, currency, success_url, cancel_url)

        case Stripe.Checkout.Session.create(checkout_params) do
          {:ok, session} ->
            {:ok, _payment} =
              upsert_payment(existing, session, participant, race, amount, currency)

            {:ok, session.url}

          {:error, %Stripe.Error{} = error} ->
            require Logger
            Logger.error("Stripe checkout session creation failed: #{error.message}")
            {:error, error.message}
        end
    end
  end

  defp get_pending_payment_for_participant(participant_id) do
    Repo.one(
      from p in Payment,
        where: p.participant_id == ^participant_id and p.status == :pending,
        order_by: [desc: p.inserted_at],
        limit: 1
    )
  end

  defp reusable_session_url(nil), do: :none

  defp reusable_session_url(%Payment{stripe_checkout_session_id: session_id}) do
    case Stripe.Checkout.Session.retrieve(session_id) do
      {:ok, %{status: "open", payment_status: "unpaid", url: url}} when is_binary(url) ->
        {:ok, url}

      _ ->
        :none
    end
  end

  # Stripe session lifetime. Kept slightly shorter than
  # `Registration.hold_ttl_seconds/0` so the session is guaranteed to be
  # closed by Stripe before our hold lapses, preventing payments from
  # landing after we'd consider the slot free.
  @stripe_session_ttl_seconds 30 * 60

  defp build_checkout_params(participant, race, amount, currency, success_url, cancel_url) do
    description =
      case participant.race_category do
        nil -> race.name
        cat -> "#{race.name} - #{cat.name}"
      end

    %{
      mode: :payment,
      success_url: success_url,
      cancel_url: cancel_url,
      expires_at: System.system_time(:second) + @stripe_session_ttl_seconds,
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
      customer_email: participant_email(participant),
      metadata: %{
        "participant_id" => to_string(participant.id),
        "race_id" => to_string(race.id)
      }
    }
  end

  defp upsert_payment(nil, session, participant, race, amount, currency) do
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
  end

  defp upsert_payment(%Payment{} = existing, session, _participant, _race, amount, currency) do
    existing
    |> Payment.changeset(%{
      stripe_checkout_session_id: session.id,
      amount_cents: amount,
      currency: String.upcase(currency)
    })
    |> Repo.update()
  end

  @doc """
  Handles a successful checkout session completion from Stripe webhook.
  Delegates to `fulfill_payment/2` which assigns a bib (if needed),
  transitions the participant to `:registered`, and auto-refunds when
  the race has filled up while the hold was expired.
  """
  def handle_checkout_completed(session_id) do
    case Repo.one(from p in Payment, where: p.stripe_checkout_session_id == ^session_id) do
      nil ->
        {:error, :payment_not_found}

      %Payment{status: :completed} = payment ->
        {:ok, payment}

      %Payment{status: :refunded} = payment ->
        {:ok, payment}

      %Payment{} = payment ->
        fulfill_payment(payment, fetch_payment_intent_id(session_id))
    end
  end

  # Drives a pending Payment to its terminal state: either `:completed`
  # (participant becomes `:registered` with a bib assigned) or `:refunded`
  # (participant stays pending without a bib and we refund the customer).
  #
  # Shared between the webhook path and `mark_paid_offline/1`. Runs bib
  # assignment inside a transaction and retries on the partial unique
  # index collision that two concurrent webhooks can trigger when both
  # compute `MAX+1 = N` for the same race.
  defp fulfill_payment(%Payment{} = payment, payment_intent_id, attempts_remaining \\ 5) do
    participant = Repo.get!(Participant, payment.participant_id)

    if should_refund?(participant) do
      refund_payment_for_full_race(payment, payment_intent_id, participant)
    else
      complete_and_register(payment, payment_intent_id, participant, attempts_remaining)
    end
  end

  # A participant who already has a bib (grandfathered `:pending_payment`
  # row from before the hold-based flow, or a participant whose bib was
  # previously assigned) keeps it and gets fulfilled normally. A
  # participant without a bib only gets one if a slot is still available
  # at the moment of payment — otherwise the hold lapsed and the race
  # filled up from under them, and we refund.
  defp should_refund?(%Participant{bib_number: bib}) when is_binary(bib), do: false

  defp should_refund?(%Participant{} = participant) do
    if hold_valid?(participant) do
      false
    else
      race = Bibtime.Races.get_race!(participant.race_id)
      Bibtime.Registration.registration_full?(race)
    end
  end

  defp hold_valid?(%Participant{hold_expires_at: nil}), do: false

  defp hold_valid?(%Participant{hold_expires_at: ts}) do
    DateTime.compare(ts, DateTime.utc_now()) == :gt
  end

  defp complete_and_register(payment, payment_intent_id, participant, attempts_remaining) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    txn =
      Repo.transaction(fn ->
        {:ok, updated_payment} =
          payment
          |> Payment.changeset(%{
            status: :completed,
            stripe_payment_intent_id: payment_intent_id,
            paid_at: now
          })
          |> Repo.update()

        participant_attrs = %{status: :registered, hold_expires_at: nil}

        participant_attrs =
          if is_nil(participant.bib_number) do
            Map.put(
              participant_attrs,
              :bib_number,
              Participants.next_bib_number(participant.race_id)
            )
          else
            participant_attrs
          end

        case participant |> Participant.changeset(participant_attrs) |> Repo.update() do
          {:ok, updated_participant} ->
            {updated_payment, updated_participant}

          {:error, changeset} ->
            Repo.rollback({:participant_update_failed, changeset})
        end
      end)

    case txn do
      {:ok, {updated_payment, updated_participant}} ->
        deliver_fulfillment_notifications_async(updated_payment, updated_participant)
        {:ok, updated_payment}

      {:error, {:participant_update_failed, %Ecto.Changeset{errors: errors}}} ->
        if bib_collision?(errors) and attempts_remaining > 0 do
          complete_and_register(payment, payment_intent_id, participant, attempts_remaining - 1)
        else
          {:error, :bib_assignment_failed}
        end

      {:error, _} = err ->
        err
    end
  end

  defp bib_collision?(errors) do
    Enum.any?(errors, fn
      {:bib_number, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  # Race filled while the participant's hold was lapsed. Refund via Stripe
  # (best-effort) and mark the payment `:refunded`. The participant row is
  # left as `:pending_payment` with no bib — their row persists so they
  # can see it in their profile and so the admin can follow up.
  defp refund_payment_for_full_race(payment, payment_intent_id, participant) do
    pi_id =
      payment_intent_id || payment.stripe_payment_intent_id ||
        fetch_payment_intent_id(payment.stripe_checkout_session_id)

    require Logger

    if is_nil(pi_id) do
      Logger.error(
        "Cannot auto-refund payment ##{payment.id}: no payment intent. Race #{participant.race_id} filled while hold for participant ##{participant.id} was expired."
      )

      {:error, :no_payment_intent_for_refund}
    else
      case Stripe.Refund.create(%{payment_intent: pi_id}) do
        {:ok, _refund} ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          {:ok, updated_payment} =
            payment
            |> Payment.changeset(%{
              status: :refunded,
              stripe_payment_intent_id: pi_id,
              paid_at: now,
              refunded_at: now
            })
            |> Repo.update()

          Logger.warning(
            "Auto-refunded payment ##{payment.id} for participant ##{participant.id}: race #{participant.race_id} filled while hold was expired"
          )

          deliver_race_filled_notice_async(participant)

          {:ok, updated_payment}

        {:error, %Stripe.Error{} = err} ->
          Logger.error(
            "Auto-refund FAILED for payment ##{payment.id} (participant ##{participant.id}): #{err.message}. Manual intervention required."
          )

          {:error, {:refund_failed, err.message}}
      end
    end
  end

  defp deliver_race_filled_notice_async(%Participant{} = participant) do
    Task.Supervisor.start_child(Bibtime.TaskSupervisor, fn ->
      require Logger
      race = Bibtime.Races.get_race!(participant.race_id)

      try do
        Bibtime.Registration.RegistrationNotifier.deliver_race_filled_notice(participant, race)
      rescue
        e -> Logger.error("Race-filled notice email failed: #{inspect(e)}")
      end
    end)

    :ok
  end

  defp deliver_fulfillment_notifications_async(%Payment{} = payment, %Participant{} = participant) do
    Task.Supervisor.start_child(Bibtime.TaskSupervisor, fn ->
      participant = Repo.preload(participant, [:race_category])
      race = Bibtime.Races.get_race!(payment.race_id)

      require Logger

      # One combined email: registration confirmation + receipt + bib number.
      # The user already received an account-creation email at form submit
      # time; sending a separate receipt would put them at three.
      try do
        Bibtime.Registration.RegistrationNotifier.deliver_paid_confirmation(
          payment,
          participant,
          race
        )
      rescue
        e -> Logger.error("Paid-registration confirmation email failed: #{inspect(e)}")
      end
    end)

    :ok
  end

  @doc """
  Marks a pending payment as paid offline (e.g. bank transfer, cash).

  Runs through the same `fulfill_payment/2` path as the Stripe webhook —
  assigns a bib if the participant doesn't have one, transitions them to
  `:registered`, clears the hold. Admins should confirm race capacity
  before marking offline since the same race-full refund guard applies
  (and there's no Stripe payment to refund, so it'd error out instead).
  """
  def mark_paid_offline(%Payment{status: :pending} = payment) do
    fulfill_payment(payment, nil)
  end

  def mark_paid_offline(%Payment{}),
    do: {:error, "Only pending payments can be marked as paid"}

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
        preload: [participant: :user]
    )
  end

  @doc """
  Returns payment summary stats for a race.
  """
  def race_payment_summary(race_id) do
    stats =
      Repo.all(
        from p in Payment,
          where: p.race_id == ^race_id,
          group_by: p.status,
          select: {p.status, count(p.id), sum(p.amount_cents)}
      )

    stats_map = Map.new(stats, fn {status, count, sum} -> {status, {count, sum || 0}} end)

    {completed_count, total_collected} = Map.get(stats_map, :completed, {0, 0})
    {pending_count, total_pending} = Map.get(stats_map, :pending, {0, 0})
    {refunded_count, total_refunded} = Map.get(stats_map, :refunded, {0, 0})

    currency =
      Repo.one(
        from p in Payment,
          where: p.race_id == ^race_id,
          select: p.currency,
          limit: 1
      )

    %{
      total_collected_cents: total_collected,
      total_pending_cents: total_pending,
      total_refunded_cents: total_refunded,
      completed_count: completed_count,
      pending_count: pending_count,
      refunded_count: refunded_count,
      currency: currency
    }
  end

  defp participant_email(participant) do
    case participant.user do
      %{email: email} when is_binary(email) and email != "" -> email
      _ -> nil
    end
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
