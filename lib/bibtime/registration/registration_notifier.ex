defmodule Bibtime.Registration.RegistrationNotifier do
  import Swoosh.Email

  alias Bibtime.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"BibTime", "contact@example.com"})
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
      date_str =
        if race.date,
          do: Calendar.strftime(race.date, "%B %d, %Y"),
          else: "TBD"

      category_name =
        if participant.race_category,
          do: participant.race_category.name,
          else: "Unassigned"

      deliver(participant.email, "Registration Confirmed — #{race.name}", """

      ==============================

      Hi #{participant.first_name},

      You are registered for #{race.name}!

      Race date: #{date_str}
      Location: #{race.location || "TBD"}
      Category: #{category_name}
      Bib number: #{participant.bib_number}

      An account has been created for you. To log in and manage
      your registration details, visit the login page and enter
      your email to receive a login link:

      /users/log-in

      Or view your registration directly:
      /races/#{race.slug}/my-registration/#{participant.confirmation_token}

      See you at the start line!

      ==============================
      """)
    end
  end
end
