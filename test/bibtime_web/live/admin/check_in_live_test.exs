defmodule BibtimeWeb.Admin.CheckInLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures

  describe "access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      conn = get(conn, ~p"/admin/races/#{race.id}/check-in")
      assert redirected_to(conn) =~ "/users/log-in"
    end

    test "regular user is redirected", %{conn: conn} do
      user = user_fixture()
      race = race_fixture(%{status: :in_progress})
      conn = conn |> log_in_user(user) |> get(~p"/admin/races/#{race.id}/check-in")
      assert redirected_to(conn) == "/"
    end
  end

  describe "mount" do
    setup %{conn: conn} do
      timer = timer_user_fixture()
      conn = log_in_user(conn, timer)
      %{conn: conn}
    end

    test "renders check-in page with race name", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      participant_fixture(race, %{bib_number: "1", first_name: "Alice", last_name: "Smith"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      html = render_async(view)

      assert html =~ "Check-In"
      assert html =~ race.name
      assert html =~ "Alice"
      assert html =~ "Smith"
    end

    test "shows checked-in count", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      p1 = participant_fixture(race, %{bib_number: "1", first_name: "Alice", last_name: "Smith"})
      participant_fixture(race, %{bib_number: "2", first_name: "Bob", last_name: "Jones"})

      Bibtime.Participants.check_in_participant(p1, "TAG001")

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      html = render_async(view)

      assert html =~ "1 / 2"
    end
  end

  describe "search" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      race = race_fixture(%{status: :in_progress})
      participant_fixture(race, %{bib_number: "10", first_name: "Alice", last_name: "Smith"})
      participant_fixture(race, %{bib_number: "20", first_name: "Bob", last_name: "Jones"})
      %{conn: conn, race: race}
    end

    test "filtering by first name", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      html = render_change(view, "search", %{"search" => "Alice"})
      assert html =~ "Alice"
      refute html =~ "Bob"
    end

    test "filtering by bib number", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      html = render_change(view, "search", %{"search" => "20"})
      assert html =~ "Bob"
      refute html =~ "Alice"
    end

    test "clearing search shows all", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_change(view, "search", %{"search" => "Alice"})
      html = render_change(view, "search", %{"search" => ""})

      assert html =~ "Alice"
      assert html =~ "Bob"
    end
  end

  describe "check-in flow" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      race = race_fixture(%{status: :in_progress})

      p1 = participant_fixture(race, %{bib_number: "42", first_name: "Test", last_name: "Runner"})
      p2 = participant_fixture(race, %{bib_number: "99", first_name: "Other", last_name: "Racer"})

      %{conn: conn, race: race, p1: p1, p2: p2}
    end

    test "selecting a participant shows scan panel", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      html = render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      assert html =~ "Selected Participant"
      assert html =~ "#42"
      assert html =~ "Test Runner"
    end

    test "deselecting clears the panel", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_click(view, "deselect_participant")
      assert html =~ "Select a participant"
      refute html =~ "Selected Participant"
    end

    test "scanning a tag checks in the participant", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_submit(view, "scan_tag", %{"tag" => "RFID123"})

      # Success banner shows
      assert html =~ "Checked in"
      assert html =~ "#42"
      assert html =~ "RFID123"

      # Participant status updated in DB
      updated = Bibtime.Participants.get_participant!(p1.id)
      assert updated.chip_id == "RFID123"
      assert updated.status == :checked_in
      assert updated.checked_in_at
    end

    test "scanning empty tag shows error", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_submit(view, "scan_tag", %{"tag" => ""})
      assert html =~ "No tag scanned"
    end

    test "scanning tag already assigned to another participant shows conflict", %{
      conn: conn,
      race: race,
      p1: p1,
      p2: p2
    } do
      Bibtime.Participants.check_in_participant(p2, "CONFLICT_TAG")

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_submit(view, "scan_tag", %{"tag" => "CONFLICT_TAG"})
      assert html =~ "already assigned"
      assert html =~ "#99"
    end

    test "scanning without selection looks up tag owner", %{conn: conn, race: race, p1: p1} do
      Bibtime.Participants.check_in_participant(p1, "LOOKUP_TAG")

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      html = render_submit(view, "scan_tag", %{"tag" => "LOOKUP_TAG"})
      # Should auto-select that participant
      assert html =~ "Selected Participant"
      assert html =~ "#42"
    end

    test "scanning unknown tag without selection shows error", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      html = render_submit(view, "scan_tag", %{"tag" => "UNKNOWN_TAG"})
      assert html =~ "not assigned"
    end

    test "stats counter increments after check-in", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_submit(view, "scan_tag", %{"tag" => "TAG001"})
      assert html =~ "1 / 2"
    end
  end

  describe "double-read protection" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      race = race_fixture(%{status: :in_progress})
      p1 = participant_fixture(race, %{bib_number: "42", first_name: "Test", last_name: "Runner"})
      %{conn: conn, race: race, p1: p1}
    end

    test "same tag scanned twice rapidly is silently ignored", %{
      conn: conn,
      race: race,
      p1: p1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      render_submit(view, "scan_tag", %{"tag" => "DOUBLE_TAG"})

      # Second scan of same tag — should be ignored (no error, no duplicate)
      # Re-select participant (first scan cleared selection on success)
      render_click(view, "select_participant", %{"id" => "#{p1.id}"})
      html = render_submit(view, "scan_tag", %{"tag" => "DOUBLE_TAG"})

      # Should not show an error — silently ignored
      refute html =~ "Failed"
      refute html =~ "No tag scanned"
    end
  end

  describe "unassign" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      race = race_fixture(%{status: :in_progress})
      p1 = participant_fixture(race, %{bib_number: "42", first_name: "Test", last_name: "Runner"})
      Bibtime.Participants.check_in_participant(p1, "ASSIGNED_TAG")
      %{conn: conn, race: race, p1: p1}
    end

    test "unassigning a tag clears chip_id and reverts status", %{
      conn: conn,
      race: race,
      p1: p1
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      render_click(view, "unassign_tag", %{"id" => "#{p1.id}"})

      updated = Bibtime.Participants.get_participant!(p1.id)
      assert is_nil(updated.chip_id)
      assert is_nil(updated.checked_in_at)
      assert updated.status == :registered
    end

    test "stats counter decrements after unassign", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      html = render_async(view)

      assert html =~ "1 / 1"

      html = render_click(view, "unassign_tag", %{"id" => "#{p1.id}"})
      assert html =~ "0 / 1"
    end
  end

  describe "PubSub real-time updates" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin)
      race = race_fixture(%{status: :in_progress})
      p1 = participant_fixture(race, %{bib_number: "42", first_name: "Test", last_name: "Runner"})
      %{conn: conn, race: race, p1: p1}
    end

    test "receives participant_checked_in via PubSub", %{conn: conn, race: race, p1: p1} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/check-in")
      _ = render_async(view)

      # Check in from another process (triggers PubSub broadcast)
      Bibtime.Participants.check_in_participant(p1, "PUBSUB_TAG")

      html = render(view)
      assert html =~ "PUBSUB_TAG"
    end
  end
end
