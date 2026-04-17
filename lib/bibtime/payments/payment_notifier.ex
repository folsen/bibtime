defmodule Bibtime.Payments.PaymentNotifier do
  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  alias Bibtime.Mailer
  alias Bibtime.Payments

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({Bibtime.SiteSettings.get().site_name, "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Sends a payment receipt email after successful payment.
  """
  def deliver_receipt(payment, participant, race) do
    if participant.email do
      amount_str = Payments.format_amount(payment.amount_cents, payment.currency)

      paid_at_str =
        if payment.paid_at,
          do: Calendar.strftime(payment.paid_at, "%B %d, %Y at %H:%M UTC"),
          else: "N/A"

      deliver(
        participant.email,
        gettext("Payment Receipt") <> " — #{race.name}",
        """

        ==============================

        #{gettext("Hi %{name},", name: participant.first_name)}

        #{gettext("Your payment has been received.")}

        #{gettext("Race")}: #{race.name}
        #{gettext("Amount")}: #{amount_str}
        #{gettext("Date")}: #{paid_at_str}
        #{gettext("Reference")}: #{payment.stripe_payment_intent_id || payment.stripe_checkout_session_id}

        #{gettext("Bib number")}: #{participant.bib_number}

        #{gettext("See you at the start line!")}

        ==============================
        """
      )
    end
  end
end
