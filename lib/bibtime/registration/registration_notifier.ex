defmodule Bibtime.Registration.RegistrationNotifier do
  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  alias Bibtime.Mailer
  alias Bibtime.SiteSettings
  alias BibtimeWeb.LocaleHelpers

  defp from_address do
    Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
  end

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({SiteSettings.get().site_name, from_address()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Sends a registration confirmation email to a participant.
  Includes login instructions so they can manage their registration.
  """
  def deliver_confirmation(participant, race) do
    if participant.email do
      locale = SiteSettings.locale_for(Map.get(participant, :user))

      Gettext.with_locale(BibtimeWeb.Gettext, locale, fn ->
        date_str =
          if race.date,
            do: LocaleHelpers.format_date(race.date),
            else: gettext("TBD")

        location_str = race.location || gettext("TBD")

        category_name =
          if participant.race_category,
            do: participant.race_category.name,
            else: gettext("Unassigned")

        deliver(
          participant.email,
          gettext("Registration Confirmed") <> " — #{race.name}",
          """

          ==============================

          #{gettext("Hi %{name},", name: participant.first_name)}

          #{gettext("You are registered for %{race}!", race: race.name)}

          #{gettext("Race date")}: #{date_str}
          #{gettext("Location")}: #{location_str}
          #{gettext("Category")}: #{category_name}
          #{gettext("Bib number")}: #{participant.bib_number}

          #{gettext("An account has been created for you. To log in and manage your registration details, visit the login page and enter your email to receive a login link:")}

          /users/log-in

          #{gettext("Or view your registration directly:")}
          /races/#{race.slug}/my-registration/#{participant.confirmation_token}

          #{gettext("See you at the start line!")}

          ==============================
          """
        )
      end)
    end
  end
end
