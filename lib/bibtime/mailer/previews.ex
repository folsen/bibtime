defmodule Bibtime.Mailer.Previews do
  @moduledoc """
  Catalog of email previews for the dev-only `/dev/emails` page.

  Each preview describes a notifier variant and exposes a zero-arg builder
  that returns a `%Swoosh.Email{}` for the given locale. The builders invoke
  the real notifier code with fixture data so previews stay in sync with
  production output.
  """

  alias Bibtime.Accounts.UserNotifier
  alias Bibtime.Payments.PaymentNotifier
  alias Bibtime.Registration.RegistrationNotifier

  def all do
    [
      %{
        key: "login_magic_link",
        title: "Magic-link login",
        description: "Sent when a confirmed user requests a login link.",
        build: fn locale ->
          UserNotifier.email_magic_link_instructions(sample_user(locale), "SAMPLE_TOKEN")
        end
      },
      %{
        key: "login_confirmation",
        title: "Account confirmation",
        description: "Sent when an unconfirmed user requests a login link.",
        build: fn locale ->
          UserNotifier.email_confirmation_instructions(sample_user(locale), "SAMPLE_TOKEN")
        end
      },
      %{
        key: "update_email",
        title: "Change email address",
        description: "Sent to the new address when a user updates their email.",
        build: fn locale ->
          UserNotifier.email_update_email_instructions(sample_user(locale), "SAMPLE_TOKEN")
        end
      },
      %{
        key: "registration_confirmation",
        title: "Registration confirmation",
        description: "Sent after a participant registers for a race.",
        build: fn locale ->
          RegistrationNotifier.email_confirmation(
            sample_participant(locale),
            sample_race()
          )
        end
      },
      %{
        key: "payment_receipt",
        title: "Payment receipt",
        description: "Sent after a successful Stripe payment.",
        build: fn locale ->
          PaymentNotifier.email_receipt(
            sample_payment(),
            sample_participant(locale),
            sample_race()
          )
        end
      }
    ]
  end

  def find(key), do: Enum.find(all(), &(&1.key == key))

  defp sample_user(locale) do
    %Bibtime.Accounts.User{
      email: "runner@example.com",
      preferred_locale: locale
    }
  end

  defp sample_race do
    %Bibtime.Races.Race{
      name: "Sample Triathlon 2026",
      slug: "sample-triathlon-2026",
      date: ~D[2026-06-15],
      location: "Stadsparken, Lund"
    }
  end

  defp sample_participant(locale) do
    %Bibtime.Participants.Participant{
      first_name: "Alex",
      last_name: "Example",
      email: "runner@example.com",
      bib_number: "42",
      confirmation_token: "SAMPLE_TOKEN",
      race_category: %Bibtime.Races.RaceCategory{name: "Olympic Men"},
      user: sample_user(locale)
    }
  end

  defp sample_payment do
    %Bibtime.Payments.Payment{
      amount_cents: 49_900,
      currency: "SEK",
      paid_at: ~U[2026-04-10 14:23:00Z],
      stripe_payment_intent_id: "pi_sample_1234567890"
    }
  end
end
