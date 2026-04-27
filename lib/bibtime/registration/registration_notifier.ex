defmodule Bibtime.Registration.RegistrationNotifier do
  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: BibtimeWeb.Endpoint,
    router: BibtimeWeb.Router,
    statics: BibtimeWeb.static_paths()

  alias Bibtime.Mailer
  alias Bibtime.SiteSettings
  alias BibtimeWeb.LocaleHelpers

  defp from_address do
    Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
  end

  defp build_email(recipient, subject, body) do
    new()
    |> to(recipient)
    |> from({SiteSettings.get().site_name, from_address()})
    |> subject(subject)
    |> text_body(body)
  end

  defp deliver(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Builds the registration confirmation email (for previews).
  """
  def email_confirmation(participant, race) do
    locale = SiteSettings.locale_for(Map.get(participant, :user))

    race =
      if Ecto.assoc_loaded?(race.categories),
        do: race,
        else: Bibtime.Repo.preload(race, :categories)

    Gettext.with_locale(BibtimeWeb.Gettext, locale, fn ->
      date_str =
        if race.date,
          do: LocaleHelpers.format_date(race.date),
          else: gettext("TBD")

      location_str = race.location || gettext("TBD")

      category_line =
        if race.categories != [] do
          name =
            if participant.race_category,
              do: participant.race_category.name,
              else: gettext("Unassigned")

          "#{gettext("Category")}: #{name}\n"
        else
          ""
        end

      build_email(
        participant.email,
        gettext("Registration Confirmed") <> " — #{race.name}",
        """
        #{gettext("Hi %{name},", name: participant.first_name)}

        #{gettext("You are registered for %{race}!", race: race.name)}

        #{gettext("Race date")}: #{date_str}
        #{gettext("Location")}: #{location_str}
        #{category_line}#{gettext("Bib number")}: #{participant.bib_number}

        #{gettext("An account has been created for you. To log in and manage your registration details, visit the login page and enter your email to receive a login link:")}

        #{url(~p"/users/log-in")}

        #{gettext("Or view your registration directly:")}
        #{url(~p"/races/#{race.slug}/my-registration/#{participant.confirmation_token}")}

        #{gettext("See you at the start line!")}
        """
      )
    end)
  end

  @doc """
  Sends a registration confirmation email to a participant.
  Includes login instructions so they can manage their registration.
  """
  def deliver_confirmation(participant, race) do
    if participant.email do
      participant |> email_confirmation(race) |> deliver()
    end
  end

  @doc """
  Builds the combined registration + receipt email sent after a successful
  Stripe payment (for previews).
  """
  def email_paid_confirmation(payment, participant, race) do
    locale = SiteSettings.locale_for(Map.get(participant, :user))

    race =
      if Ecto.assoc_loaded?(race.categories),
        do: race,
        else: Bibtime.Repo.preload(race, :categories)

    Gettext.with_locale(BibtimeWeb.Gettext, locale, fn ->
      date_str =
        if race.date,
          do: LocaleHelpers.format_date(race.date),
          else: gettext("TBD")

      location_str = race.location || gettext("TBD")

      category_line =
        if race.categories != [] do
          name =
            if participant.race_category,
              do: participant.race_category.name,
              else: gettext("Unassigned")

          "#{gettext("Category")}: #{name}\n"
        else
          ""
        end

      amount_str = Bibtime.Payments.format_amount(payment.amount_cents, payment.currency)

      paid_at_str =
        if payment.paid_at do
          date = LocaleHelpers.format_date(DateTime.to_date(payment.paid_at))
          time = Calendar.strftime(payment.paid_at, "%H:%M UTC")
          "#{date}, #{time}"
        else
          gettext("N/A")
        end

      reference = payment.stripe_payment_intent_id || payment.stripe_checkout_session_id

      build_email(
        participant.email,
        gettext("You're registered!") <> " — #{race.name}",
        """
        #{gettext("Hi %{name},", name: participant.first_name)}

        #{gettext("You are registered for %{race}!", race: race.name)}

        #{gettext("Race date")}: #{date_str}
        #{gettext("Location")}: #{location_str}
        #{category_line}#{gettext("Bib number")}: #{participant.bib_number}

        #{gettext("View your registration:")}
        #{url(~p"/races/#{race.slug}/my-registration/#{participant.confirmation_token}")}

        --

        #{gettext("Payment receipt")}
        #{gettext("Amount")}: #{amount_str}
        #{gettext("Date")}: #{paid_at_str}
        #{gettext("Reference")}: #{reference}

        #{gettext("See you at the start line!")}
        """
      )
    end)
  end

  @doc """
  Sends the combined "you're registered + receipt" email after a successful
  payment. Replaces the previously-separate confirmation and receipt emails
  for paid registrations.
  """
  def deliver_paid_confirmation(payment, participant, race) do
    if participant.email do
      payment |> email_paid_confirmation(participant, race) |> deliver()
    end
  end

  @doc """
  Builds the race-filled-and-refunded email (for previews).
  """
  def email_race_filled(participant, race) do
    locale = SiteSettings.locale_for(Map.get(participant, :user))

    Gettext.with_locale(BibtimeWeb.Gettext, locale, fn ->
      build_email(
        participant.email,
        gettext("Registration could not be completed") <> " — #{race.name}",
        """
        #{gettext("Hi %{name},", name: participant.first_name)}

        #{gettext("Unfortunately %{race} filled up before your payment was processed, so your payment has been automatically refunded.", race: race.name)}

        #{gettext("The refund should appear on your statement within a few business days. We're sorry for the inconvenience.")}

        #{gettext("Race page:")} #{url(~p"/races/#{race.slug}")}
        """
      )
    end)
  end

  @doc """
  Sends a notice that the participant's payment was refunded because the
  race filled up before their (lapsed) hold could be renewed at payment.
  """
  def deliver_race_filled_notice(participant, race) do
    if participant.email do
      participant |> email_race_filled(race) |> deliver()
    end
  end
end
