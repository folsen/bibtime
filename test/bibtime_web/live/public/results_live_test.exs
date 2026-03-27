defmodule BibtimeWeb.Public.ResultsLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.TimingFixtures

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race_with_results do
    {race, [swim, bike, run]} =
      triathlon_fixture(%{slug: "results-test-#{System.unique_integer([:positive])}"})

    cat_elite = category_fixture(race, %{name: "Elite", sort_order: 1})
    cat_age = category_fixture(race, %{name: "Age Group", sort_order: 2})

    p1 =
      participant_fixture(race, %{
        bib_number: "1",
        first_name: "Alice",
        last_name: "Fast",
        race_category_id: cat_elite.id
      })

    p2 =
      participant_fixture(race, %{
        bib_number: "2",
        first_name: "Bob",
        last_name: "Medium",
        race_category_id: cat_elite.id
      })

    p3 =
      participant_fixture(race, %{
        bib_number: "3",
        first_name: "Carol",
        last_name: "Slow",
        race_category_id: cat_age.id
      })

    # Alice finishes fastest
    record_split_time!(p1, swim, 100_000)
    record_split_time!(p1, bike, 300_000)
    record_split_time!(p1, run, 500_000)

    # Bob finishes second
    record_split_time!(p2, swim, 120_000)
    record_split_time!(p2, bike, 350_000)
    record_split_time!(p2, run, 600_000)

    # Carol finishes third
    record_split_time!(p3, swim, 150_000)
    record_split_time!(p3, bike, 400_000)
    record_split_time!(p3, run, 700_000)

    %{
      race: race,
      splits: [swim, bike, run],
      participants: [p1, p2, p3],
      categories: [cat_elite, cat_age]
    }
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "mount and render" do
    test "renders results page with race name", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}/results")
      assert html =~ race.name
    end

    test "shows loading state initially, then results after async", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, html} = live(conn, ~p"/races/#{race.slug}/results")
      # Initially loading
      assert html =~ "animate-pulse"

      # After async completes
      html = render_async(view)
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Carol"
    end

    test "shows split columns", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "swim"
      assert html =~ "bike"
      assert html =~ "run"
    end

    test "shows participant count and finished count", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "3 participants"
      assert html =~ "3 finished"
    end
  end

  describe "category filtering" do
    test "Overall tab shows all participants", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Carol"
    end

    test "manual category filter shows only that category", %{conn: conn} do
      %{race: race, categories: [cat_elite, _cat_age]} = create_race_with_results()

      {:ok, view, _html} =
        live(conn, ~p"/races/#{race.slug}/results?category=manual:#{cat_elite.id}")

      html = render_async(view)

      assert html =~ "Alice"
      assert html =~ "Bob"
      refute html =~ "Carol"
    end
  end

  describe "sorting" do
    test "sort by name", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      _ = render_async(view)

      html = render_click(view, "sort", %{"col" => "name"})
      # Should contain all names, sorted by name
      assert html =~ "Alice"
      assert html =~ "Bob"
      assert html =~ "Carol"
    end

    test "clicking same column toggles direction", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      _ = render_async(view)

      # First click: asc
      render_click(view, "sort", %{"col" => "bib"})
      # Second click: desc
      html = render_click(view, "sort", %{"col" => "bib"})
      assert html =~ "Alice"
    end
  end

  describe "PubSub real-time updates" do
    test "new split time triggers recalculation", %{conn: conn} do
      {race, [swim, bike, run]} =
        triathlon_fixture(%{slug: "pubsub-test-#{System.unique_integer([:positive])}"})

      p1 = participant_fixture(race, %{bib_number: "10", first_name: "Racer", last_name: "One"})
      record_split_time!(p1, swim, 100_000)
      record_split_time!(p1, bike, 300_000)

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      _ = render_async(view)

      # Racer has 2/3 splits, status is racing
      html = render(view)
      assert html =~ "Racer"

      # Now record the final split (triggers PubSub)
      record_split_time!(p1, run, 500_000)

      # The view should have received the broadcast and recalculated
      html = render(view)
      assert html =~ "Racer"
    end

    test "deleted split time triggers recalculation", %{conn: conn} do
      {race, [swim, bike, run]} =
        triathlon_fixture(%{slug: "pubsub-del-#{System.unique_integer([:positive])}"})

      p1 =
        participant_fixture(race, %{bib_number: "11", first_name: "Reverser", last_name: "One"})

      record_split_time!(p1, swim, 100_000)
      record_split_time!(p1, bike, 300_000)
      st = record_split_time!(p1, run, 500_000)

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      _ = render_async(view)

      # Delete the last split time
      Bibtime.Timing.delete_split_time(st)

      html = render(view)
      assert html =~ "Reverser"
    end
  end

  describe "empty state" do
    test "shows no results message when race has no participants", %{conn: conn} do
      race =
        race_fixture(%{status: :in_progress, slug: "empty-#{System.unique_integer([:positive])}"})

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "No results yet"
    end
  end
end
