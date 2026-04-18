defmodule BibtimeWeb.Admin.TimingLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.TimingFixtures

  describe "access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      conn = get(conn, ~p"/admin/races/#{race.id}/timing")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "regular user is redirected", %{conn: conn} do
      user = user_fixture()
      race = race_fixture(%{status: :in_progress})
      conn = conn |> log_in_user(user) |> get(~p"/admin/races/#{race.id}/timing")
      assert redirected_to(conn) == "/"
    end
  end

  describe "mount (timer user)" do
    setup %{conn: conn} do
      timer = timer_user_fixture()
      conn = log_in_user(conn, timer)
      %{conn: conn, user: timer}
    end

    test "renders timing console for race without start", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      split_fixture(race, %{name: "Swim", short_name: "swim", leg_type: :swim, sort_order: 1})

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      assert html =~ "Timing Console"
      assert html =~ "Start Race"
      assert html =~ race.name
    end

    test "renders timing console with running clock when race started", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      split_fixture(race, %{name: "Swim", short_name: "swim", leg_type: :swim, sort_order: 1})
      start_race_fixture(race, ~U[2026-06-01 08:00:00Z])

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      assert html =~ "Elapsed since gun start"
      assert html =~ "Bib Number"
    end

    test "finished race hides gun timer and start button", %{conn: conn} do
      race = race_fixture(%{status: :finished})
      split_fixture(race, %{name: "Swim", short_name: "swim", leg_type: :swim, sort_order: 1})

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      assert html =~ "Race is finished"
      refute html =~ "Start Race"
      refute html =~ "Elapsed since gun start"
      refute html =~ "Enter bib number"
    end

    test "finished race with a prior race_start still hides the clock", %{conn: conn} do
      race = race_fixture(%{status: :finished})
      split_fixture(race, %{name: "Swim", short_name: "swim", leg_type: :swim, sort_order: 1})
      start_race_fixture(race, ~U[2026-06-01 08:00:00Z])

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      refute html =~ "Elapsed since gun start"
      assert html =~ "Race is finished"
    end
  end

  describe "start_race event" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      %{conn: conn, user: admin}
    end

    test "starting the race shows the clock and bib input", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      split_fixture(race, %{name: "Run", short_name: "run", leg_type: :run, sort_order: 1})

      {:ok, view, html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      assert html =~ "Start Race"

      html = render_click(view, "start_race")
      assert html =~ "Elapsed since gun start"
      assert html =~ "Bib Number"
    end
  end

  describe "recording times" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)

      {race, [swim, bike, run]} = triathlon_fixture()
      start_race_fixture(race, ~U[2026-06-01 08:00:00Z])

      participant =
        participant_fixture(race, %{bib_number: "42", first_name: "Test", last_name: "Runner"})

      %{conn: conn, race: race, swim: swim, bike: bike, run: run, participant: participant}
    end

    test "recording a time for a valid bib clears input", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")

      # Wait for async loading
      _ = render_async(view)

      html = render_submit(view, "record_time", %{"bib" => "42"})
      refute html =~ "Unknown bib number"
    end

    test "recording time for unknown bib shows error", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      html = render_submit(view, "record_time", %{"bib" => "999"})
      assert html =~ "Unknown bib number"
    end

    test "recording time with empty bib shows error", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      html = render_submit(view, "record_time", %{"bib" => ""})
      assert html =~ "enter a bib number"
    end

    test "select_split changes active split", %{conn: conn, race: race, bike: bike} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      html = render_click(view, "select_split", %{"split-id" => "#{bike.id}"})
      # Bike split button should now be active (has primary class)
      assert html =~ "Bike"
    end

    test "quick_bib populates bib input", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      html = render_click(view, "quick_bib", %{"bib" => "42"})
      assert html =~ "42"
    end
  end

  describe "PubSub real-time updates" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)

      {race, [swim, _bike, _run]} = triathlon_fixture()
      start_race_fixture(race, ~U[2026-06-01 08:00:00Z])

      participant =
        participant_fixture(race, %{bib_number: "7", first_name: "Live", last_name: "Update"})

      %{conn: conn, race: race, swim: swim, participant: participant}
    end

    test "receives split_time_recorded via PubSub", %{
      conn: conn,
      race: race,
      swim: swim,
      participant: participant
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      # Record a time (which triggers PubSub broadcast)
      _split_time = record_split_time!(participant, swim, 120_000)

      # The LiveView should receive the broadcast and update
      html = render(view)
      assert html =~ "7"
      assert html =~ "Swim"
    end

    test "receives split_time_deleted via PubSub", %{
      conn: conn,
      race: race,
      swim: swim,
      participant: participant
    } do
      split_time = record_split_time!(participant, swim, 120_000)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      # Delete the split time (triggers PubSub broadcast)
      Bibtime.Timing.delete_split_time(split_time)

      html = render(view)
      # The entry should be removed from recent entries
      refute html =~ "entry-#{split_time.id}"
    end
  end

  describe "delete_entry event" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)

      {race, [swim, _bike, _run]} = triathlon_fixture()
      start_race_fixture(race, ~U[2026-06-01 08:00:00Z])

      participant =
        participant_fixture(race, %{bib_number: "5", first_name: "Del", last_name: "Test"})

      split_time = record_split_time!(participant, swim, 100_000)

      %{conn: conn, race: race, split_time: split_time}
    end

    test "deleting an entry removes it", %{conn: conn, race: race, split_time: split_time} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/timing")
      _ = render_async(view)

      render_click(view, "delete_entry", %{"id" => "#{split_time.id}"})

      assert_raise Ecto.NoResultsError, fn ->
        Bibtime.Timing.get_split_time!(split_time.id)
      end
    end
  end
end
