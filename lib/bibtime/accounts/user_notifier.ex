defmodule Bibtime.Accounts.UserNotifier do
  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  alias Bibtime.Mailer
  alias Bibtime.SiteSettings
  alias Bibtime.Accounts.User

  defp from_address do
    Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
  end

  # Delivers the email using the application mailer.
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

  defp with_recipient_locale(user, fun) do
    Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(user), fun)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Update email instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can change your email by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this change, please ignore this.")}

      ==============================
      """)
    end)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Log in instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can log into your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't request this email, please ignore this.")}

      ==============================
      """)
    end)
  end

  defp deliver_confirmation_instructions(user, url) do
    with_recipient_locale(user, fn ->
      deliver(user.email, gettext("Confirmation instructions"), """

      ==============================

      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can confirm your account by visiting the URL below:")}

      #{url}

      #{gettext("If you didn't create an account with us, please ignore this.")}

      ==============================
      """)
    end)
  end
end
