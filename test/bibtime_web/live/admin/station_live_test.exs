defmodule BibtimeWeb.Admin.StationLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.TimingFixtures

  alias Bibtime.Timing

  describe "GlobalIndex — access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      conn = get(conn, ~p"/admin/stations")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  describe "GlobalIndex — admin" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      %{conn: log_in_user(conn, admin)}
    end

    test "renders global stations page and allows creating a station", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/stations")

      assert html =~ "Timing Stations"

      html =
        view
        |> form("form", station: %{"name" => "Finish Reader"})
        |> render_submit()

      assert html =~ "Finish Reader"
      assert html =~ "copy the token now"

      stations = Timing.list_all_stations()
      assert Enum.any?(stations, &(&1.name == "Finish Reader"))
    end

    test "allows creating a station with a manual token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/stations")

      view |> element("button", "Enter token manually") |> render_click()

      html =
        view
        |> form("form", station: %{"name" => "Manual Station", "token" => "my-custom-token-123"})
        |> render_submit()

      assert html =~ "Manual Station"

      station = Timing.get_station_by_token("my-custom-token-123")
      assert station
      assert station.name == "Manual Station"
    end

    test "allows deleting a station", %{conn: conn} do
      station = station_fixture(%{"name" => "Doomed"})
      {:ok, view, html} = live(conn, ~p"/admin/stations")

      assert html =~ "Doomed"

      view |> element("button", "Delete") |> render_click()

      refute render(view) =~ "Doomed"
      assert Timing.list_all_stations() == []
      assert is_nil(Bibtime.Repo.get(Timing.TimingStation, station.id))
    end
  end

  describe "Race-level Index — access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      conn = get(conn, ~p"/admin/races/#{race.id}/stations")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  describe "Race-level Index — admin" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      {race, [swim, _bike, _run]} = triathlon_fixture()
      %{conn: log_in_user(conn, admin), race: race, swim: swim}
    end

    test "renders the assignment page with splits", %{conn: conn, race: race} do
      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/stations")

      assert html =~ "Timing Stations"
      assert html =~ race.name
    end

    test "can assign and unassign a station to a split", %{
      conn: conn,
      race: race,
      swim: swim
    } do
      station = station_fixture(%{"name" => "Swim Reader"})
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/stations")

      html =
        view
        |> form("#assign-split-#{swim.id}", %{station_id: station.id})
        |> render_submit()

      assert html =~ "Swim Reader"
      assert html =~ "assigned"

      # Verify assignment persisted
      [assigned] = Timing.list_stations_for_race(race.id)
      assert assigned.id == station.id
      assert assigned.assigned_split_id == swim.id

      # Unassign
      view |> element("button", "Unassign") |> render_click()
      assert Timing.list_stations_for_race(race.id) == []
    end
  end
end
