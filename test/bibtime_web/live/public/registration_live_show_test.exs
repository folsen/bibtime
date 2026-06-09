defmodule BibtimeWeb.Public.RegistrationLive.ShowTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.RacesFixtures

  alias Bibtime.Registration
  alias Bibtime.Repo
  alias Bibtime.Payments.Payment

  defp register!(race, attrs \\ %{}) do
    {:ok, participant} =
      Registration.register_participant(
        race,
        Map.merge(%{first_name: "Alice", last_name: "Smith", email: "alice@example.com"}, attrs)
      )

    participant
  end

  describe "confirmation page" do
    test "renders for a valid confirmation token", %{conn: conn} do
      race = race_fixture(%{status: :registration_open})
      participant = register!(race)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/races/#{race.slug}/register/confirmation/#{participant.confirmation_token}"
        )

      assert html =~ "Registered"
      assert html =~ "Alice"
    end

    test "redirects to the race page when the token is unknown", %{conn: conn} do
      race = race_fixture(%{status: :registration_open})

      assert {:error, {kind, %{to: to}}} =
               live(conn, ~p"/races/#{race.slug}/register/confirmation/no-such-token")

      assert kind in [:redirect, :live_redirect]
      assert to == ~p"/races/#{race.slug}"
    end

    test "does not resolve a participant by integer id (enumeration is closed)", %{conn: conn} do
      race = race_fixture(%{status: :registration_open})
      participant = register!(race)

      # Walking sequential ids must not reach anyone's confirmation page.
      assert {:error, {kind, %{to: _}}} =
               live(conn, ~p"/races/#{race.slug}/register/confirmation/#{participant.id}")

      assert kind in [:redirect, :live_redirect]
    end

    test "redirects when the token belongs to a different race", %{conn: conn} do
      race_a = race_fixture(%{status: :registration_open})
      race_b = race_fixture(%{status: :registration_open})
      participant = register!(race_a)

      assert {:error, {kind, %{to: _}}} =
               live(
                 conn,
                 ~p"/races/#{race_b.slug}/register/confirmation/#{participant.confirmation_token}"
               )

      assert kind in [:redirect, :live_redirect]
    end

    test "the dead (HTTP) render does not reconcile payment against Stripe", %{conn: conn} do
      race =
        race_fixture(%{
          status: :registration_open,
          payment_required: true,
          entry_fee_cents: 10_000
        })

      participant = register!(race)

      Repo.insert!(
        Payment.changeset(%Payment{}, %{
          participant_id: participant.id,
          race_id: race.id,
          amount_cents: 10_000,
          currency: "SEK",
          status: :pending
        })
      )

      # connected?/1 is false on the disconnected render, so the page must
      # render from DB state without calling Stripe (which is unconfigured in
      # tests and would otherwise blow up here).
      conn =
        get(conn, ~p"/races/#{race.slug}/register/confirmation/#{participant.confirmation_token}")

      assert html_response(conn, 200) =~ "Awaiting Payment"
    end
  end
end
