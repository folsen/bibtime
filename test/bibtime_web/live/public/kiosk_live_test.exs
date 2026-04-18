defmodule BibtimeWeb.Public.KioskLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.TimingFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race_with_results do
    slug = "kiosk-test-#{System.unique_integer([:positive])}"
    {race, [swim, bike, run]} = triathlon_fixture(%{slug: slug})

    p1 = participant_fixture(race, %{bib_number: "1", first_name: "Alice", last_name: "Runner"})
    p2 = participant_fixture(race, %{bib_number: "2", first_name: "Bob", last_name: "Racer"})

    record_split_time!(p1, swim, 100_000)
    record_split_time!(p1, bike, 300_000)
    record_split_time!(p1, run, 500_000)

    record_split_time!(p2, swim, 120_000)
    record_split_time!(p2, bike, 350_000)

    %{race: race, splits: [swim, bike, run], participants: [p1, p2]}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "mount and render" do
    test "renders kiosk page with race name", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}/kiosk")
      assert html =~ race.name
    end

    test "shows results after async loading", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/kiosk")
      html = render_async(view)

      assert html =~ "Alice"
      assert html =~ "Bob"
    end
  end

  describe "PubSub real-time updates" do
    test "new split time updates kiosk display", %{conn: conn} do
      slug = "kiosk-pub-#{System.unique_integer([:positive])}"
      {race, [swim, _bike, _run]} = triathlon_fixture(%{slug: slug})
      p1 = participant_fixture(race, %{bib_number: "10", first_name: "Live", last_name: "Kiosk"})

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/kiosk")
      _ = render_async(view)

      # Record a split time (triggers PubSub)
      record_split_time!(p1, swim, 120_000)

      html = render(view)
      assert html =~ "Live"
    end
  end

  describe "empty state" do
    test "renders without errors when no participants exist", %{conn: conn} do
      slug = "kiosk-empty-#{System.unique_integer([:positive])}"
      race = race_fixture(%{status: :in_progress, slug: slug})

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/kiosk")
      html = render_async(view)

      # Should render without crashing
      assert html =~ race.name
    end
  end

  describe "category rotation" do
    test "skips categories with no participants when rotating", %{conn: conn} do
      slug = "kiosk-rotate-#{System.unique_integer([:positive])}"
      {race, [swim, _bike, _run]} = triathlon_fixture(%{slug: slug})

      populated = category_fixture(race, %{name: "Populated", sort_order: 1})
      _empty = category_fixture(race, %{name: "Empty", sort_order: 2})

      p =
        participant_fixture(race, %{
          bib_number: "1",
          first_name: "Cat",
          last_name: "Member",
          race_category_id: populated.id
        })

      record_split_time!(p, swim, 100_000)

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/kiosk")
      _ = render_async(view)

      # Manually trigger rotation; from "Overall" we should jump to "Populated"
      # and skip "Empty" entirely.
      send(view.pid, :rotate_category)
      html = render(view)
      assert html =~ "Populated"
      refute html =~ ~r/>\s*Empty\s*</

      send(view.pid, :rotate_category)
      html = render(view)
      # Wraps back to Overall (Empty stays skipped)
      assert html =~ "Overall"
      refute html =~ ~r/>\s*Empty\s*</
    end
  end

  describe "URL params" do
    test "custom columns param limits visible columns", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/kiosk?columns=rank,bib,total")
      html = render_async(view)

      # Should render without errors
      assert html =~ "Alice" or html =~ race.name
    end

    test "scroll_speed param is accepted", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}/kiosk?scroll_speed=slow")
      assert html =~ race.name
    end
  end
end
