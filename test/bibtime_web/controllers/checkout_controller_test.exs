defmodule BibtimeWeb.CheckoutControllerTest do
  use BibtimeWeb.ConnCase

  import Bibtime.RacesFixtures

  alias Bibtime.Registration

  defp paid_race do
    race_fixture(%{status: :registration_open, payment_required: true, entry_fee_cents: 10_000})
  end

  defp register!(race, attrs \\ %{}) do
    {:ok, participant} =
      Registration.register_participant(
        race,
        Map.merge(%{first_name: "Alice", last_name: "Smith", email: "alice@example.com"}, attrs)
      )

    participant
  end

  describe "GET /races/:slug/checkout/:token" do
    test "an unknown token redirects to registration instead of starting checkout",
         %{conn: conn} do
      race = paid_race()

      conn = get(conn, ~p"/races/#{race.slug}/checkout/no-such-token")

      assert redirected_to(conn) == ~p"/races/#{race.slug}/register"
    end

    test "a participant integer id is not accepted (enumeration is closed)", %{conn: conn} do
      race = paid_race()
      participant = register!(race)

      conn = get(conn, ~p"/races/#{race.slug}/checkout/#{participant.id}")

      assert redirected_to(conn) == ~p"/races/#{race.slug}/register"
    end

    test "a token belonging to another race is rejected", %{conn: conn} do
      race_a = paid_race()
      race_b = paid_race()
      participant = register!(race_a)

      conn = get(conn, ~p"/races/#{race_b.slug}/checkout/#{participant.confirmation_token}")

      assert redirected_to(conn) == ~p"/races/#{race_b.slug}/register"
    end
  end
end
