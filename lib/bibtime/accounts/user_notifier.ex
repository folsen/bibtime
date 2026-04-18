defmodule Bibtime.Accounts.UserNotifier do
  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: BibtimeWeb.Endpoint,
    router: BibtimeWeb.Router,
    statics: BibtimeWeb.static_paths()

  alias Bibtime.Mailer
  alias Bibtime.SiteSettings
  alias Bibtime.Accounts.User

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

  defp with_recipient_locale(user, fun) do
    Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(user), fun)
  end

  @doc """
  Builds the email struct for `deliver_update_email_instructions/2` (for previews).
  """
  def email_update_email_instructions(user, encoded_token) do
    with_recipient_locale(user, fn ->
      build_email(user.email, gettext("Update email instructions"), """
      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can change your email by visiting the URL below:")}

      #{url(~p"/users/settings/confirm-email/#{encoded_token}")}

      #{gettext("If you didn't request this change, please ignore this.")}
      """)
    end)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, encoded_token) do
    user |> email_update_email_instructions(encoded_token) |> deliver()
  end

  @doc """
  Builds the email struct for a magic-link login (for previews).
  """
  def email_magic_link_instructions(user, encoded_token) do
    with_recipient_locale(user, fn ->
      build_email(user.email, gettext("Log in instructions"), """
      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can log into your account by visiting the URL below:")}

      #{url(~p"/users/log-in/#{encoded_token}")}

      #{gettext("If you didn't request this email, please ignore this.")}
      """)
    end)
  end

  @doc """
  Builds the email struct for an account confirmation link (for previews).
  """
  def email_confirmation_instructions(user, encoded_token) do
    with_recipient_locale(user, fn ->
      build_email(user.email, gettext("Confirmation instructions"), """
      #{gettext("Hi %{email},", email: user.email)}

      #{gettext("You can confirm your account by visiting the URL below:")}

      #{url(~p"/users/log-in/#{encoded_token}")}

      #{gettext("If you didn't create an account with us, please ignore this.")}
      """)
    end)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(%User{confirmed_at: nil} = user, encoded_token) do
    user |> email_confirmation_instructions(encoded_token) |> deliver()
  end

  def deliver_login_instructions(user, encoded_token) do
    user |> email_magic_link_instructions(encoded_token) |> deliver()
  end
end
