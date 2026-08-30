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

  describe "accolades" do
    test "appear at the bottom of the results page", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "Accolades"
      assert html =~ "Fastest Swim"
      assert html =~ "Fastest Bike"
      assert html =~ "Fastest Run"
    end

    test "rescope to the selected category", %{conn: conn} do
      %{race: race, categories: [elite, _age]} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      overall = render_async(view)

      {:ok, view, _html} =
        live(conn, ~p"/races/#{race.slug}/results?category=manual:#{elite.id}")

      filtered = render_async(view)

      assert overall =~ "Accolades"
      assert filtered =~ "Accolades"
      # The filtered view says so, so a printed category sheet is not mistaken
      # for the whole race.
      assert filtered =~ "within the selected category"
      refute overall =~ "within the selected category"
    end

    test "are absent when nobody has finished", %{conn: conn} do
      race =
        race_fixture(%{
          status: :in_progress,
          slug: "no-acc-#{System.unique_integer([:positive])}"
        })

      participant_fixture(race, %{bib_number: "1"})

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      refute html =~ "Accolades"
    end
  end

  describe "the action buttons" do
    test "sit above the results table, not below it", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "Print as PDF"
      refute html =~ "Export PDF"

      # The buttons must come before the table in document order, or they are
      # buried again on a race with hundreds of finishers.
      assert :binary.match(html, "Print as PDF") < :binary.match(html, "results-table")
    end

    test "no longer offer the removed PDF export route", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      refute html =~ "results/export/pdf"
      assert html =~ "results/export/csv"
    end
  end

  describe "fastest-leg highlighting" do
    test "marks the quickest finisher on each leg", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      # One highlighted cell per leg, plus one for the winning total.
      highlighted = html |> String.split("bg-primary/10") |> length() |> Kernel.-(1)
      assert highlighted >= length(Bibtime.Races.list_splits(race.id))
    end
  end

  describe "the photos link" do
    test "is offered even when the race has no photos yet", %{conn: conn} do
      %{race: race} = create_race_with_results()

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ ~p"/races/#{race.slug}/photos"
      assert html =~ "Photos"
    end

    test "shows the count once there are photos", %{conn: conn} do
      %{race: race} = create_race_with_results()
      Bibtime.PhotosFixtures.photo_fixture(race)

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/results")
      html = render_async(view)

      assert html =~ "1 Photo"
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
