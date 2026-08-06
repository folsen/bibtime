defmodule BibtimeWeb.Admin.ReadLogLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.TimingFixtures

  alias Bibtime.Timing

  describe "access control" do
    test "unauthenticated user is redirected", %{conn: conn} do
      race = race_fixture(%{status: :in_progress})
      conn = get(conn, ~p"/admin/races/#{race.id}/reads")
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  describe "read log feed" do
    setup %{conn: conn} do
      timer = timer_user_fixture()
      {race, [swim, bike, run]} = triathlon_fixture()

      started_at =
        DateTime.utc_now()
        |> DateTime.add(-4 * 3600, :second)
        |> DateTime.truncate(:second)

      start_race_fixture(race, started_at)

      station =
        station_fixture(%{"name" => "Bike/Run Mat"})
        |> assign_station!(bike)
        |> assign_station!(run)

      %{
        conn: log_in_user(conn, timer),
        race: race,
        swim: swim,
        station: station,
        started_at: started_at
      }
    end

    test "renders empty state before any reads", %{conn: conn, race: race} do
      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/reads")

      assert html =~ "Read Log"
      assert html =~ "Waiting for reads"
    end

    test "shows recorded, duplicate, and unmatched events live", %{
      conn: conn,
      race: race,
      station: station,
      started_at: started_at
    } do
      _ = participant_fixture(race, %{chip_id: "E200RL1", bib_number: "77", first_name: "Read"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/reads")

      {:ok, :recorded, _p, _st} =
        Timing.ingest_chip_read(station, %{
          "chip_id" => "E200RL1",
          "read_at" => started_at |> DateTime.add(600, :second) |> DateTime.to_iso8601()
        })

      html = render(view)
      assert html =~ "Recorded"
      assert html =~ "Bike/Run Mat"
      assert html =~ "77"

      # Re-read 60s later → lockout duplicate
      {:ok, :duplicate, _p} =
        Timing.ingest_chip_read(station, %{
          "chip_id" => "E200RL1",
          "read_at" => started_at |> DateTime.add(660, :second) |> DateTime.to_iso8601()
        })

      html = render(view)
      assert html =~ "Duplicate"
      assert html =~ "re-read 60s after last pass"

      {:ok, :unmatched} =
        Timing.ingest_chip_read(station, %{
          "chip_id" => "E200NOPE",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      html = render(view)
      assert html =~ "Unmatched"
      assert html =~ "E200NOPE"
    end

    test "filters events by outcome", %{
      conn: conn,
      race: race,
      station: station,
      started_at: started_at
    } do
      _ = participant_fixture(race, %{chip_id: "E200RL2", bib_number: "78"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/reads")

      {:ok, :recorded, _p, _st} =
        Timing.ingest_chip_read(station, %{
          "chip_id" => "E200RL2",
          "read_at" => started_at |> DateTime.add(600, :second) |> DateTime.to_iso8601()
        })

      {:ok, :unmatched} =
        Timing.ingest_chip_read(station, %{
          "chip_id" => "E200GHOST",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      html = render_click(view, "set_filter", %{"filter" => "unmatched"})
      assert html =~ "E200GHOST"
      refute html =~ "E200RL2"

      html = render_click(view, "set_filter", %{"filter" => "recorded"})
      assert html =~ "E200RL2"
      refute html =~ "E200GHOST"
    end
  end
end
