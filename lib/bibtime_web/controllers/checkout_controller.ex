defmodule BibtimeWeb.CheckoutController do
  @moduledoc """
  Bridge between the registration LiveView and Stripe Checkout.

  Exists so the Stripe redirect goes through a regular HTTP request, which
  lets us write a session cookie before sending the user off to Stripe. If
  they bail on Stripe and hit the browser back button, the registration
  form re-mounts and reads `:pending_participant_id` from the session to
  pre-fill itself instead of greeting them with an empty form.
  """
  use BibtimeWeb, :controller

  alias Bibtime.{Participants, Payments, Races}

  def start(conn, %{"slug" => slug, "participant_id" => participant_id}) do
    race = Races.get_race_by_slug!(slug)
    participant = Participants.get_participant!(participant_id)

    if participant.race_id != race.id do
      conn
      |> put_flash(:error, gettext("Registration not found"))
      |> redirect(to: ~p"/races/#{race.slug}/register")
    else
      base_url = BibtimeWeb.Endpoint.url()
      success_url = base_url <> ~p"/races/#{race.slug}/register/confirmation/#{participant.id}"
      cancel_url = base_url <> ~p"/races/#{race.slug}/register/confirmation/#{participant.id}"

      case Payments.create_checkout_session(participant, race, success_url, cancel_url) do
        {:ok, checkout_url} ->
          conn
          |> put_session(:pending_participant_id, participant.id)
          |> redirect(external: checkout_url)

        {:error, reason} ->
          conn
          |> put_flash(:error, gettext("Payment setup failed: %{reason}", reason: reason))
          |> redirect(to: ~p"/races/#{race.slug}/register/confirmation/#{participant.id}")
      end
    end
  end
end
