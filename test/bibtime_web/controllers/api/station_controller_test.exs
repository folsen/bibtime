defmodule BibtimeWeb.API.StationControllerTest do
  use BibtimeWeb.ConnCase, async: true

  alias Bibtime.Timing

  import Bibtime.ParticipantsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.TimingFixtures

  defp setup_context(_) do
    {race, [swim, _bike, _run]} = triathlon_fixture()

    started_at =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    start_race_fixture(race, started_at)

    station = station_fixture(%{"name" => "Swim In"})
    {:ok, station} = Timing.assign_station(station, swim)

    participant =
      participant_fixture(race, %{
        chip_id: "E200API",
        bib_number: "99",
        first_name: "Anna",
        last_name: "Test"
      })

    %{race: race, split: swim, station: station, participant: participant}
  end

  describe "POST /api/stations/:token/reads" do
    setup [:setup_context]

    test "records a read and returns participant info", %{conn: conn, station: station} do
      conn =
        post(conn, ~p"/api/stations/#{station.token}/reads", %{
          "chip_id" => "E200API",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "rssi" => -42
        })

      assert %{
               "status" => "recorded",
               "participant_bib" => "99",
               "participant_name" => "Anna Test",
               "elapsed_ms" => ms
             } = json_response(conn, 200)

      assert is_integer(ms)
    end

    test "returns duplicate when split already recorded", %{
      conn: conn,
      station: station,
      participant: participant,
      split: split
    } do
      _ = record_split_time!(participant, split, 1_234)

      conn =
        post(conn, ~p"/api/stations/#{station.token}/reads", %{
          "chip_id" => "E200API",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert %{"status" => "duplicate", "participant_bib" => "99"} = json_response(conn, 200)
    end

    test "returns unmatched when chip has no participant", %{conn: conn, station: station} do
      conn =
        post(conn, ~p"/api/stations/#{station.token}/reads", %{
          "chip_id" => "UNKNOWN_TAG",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert %{"status" => "unmatched", "chip_id" => "UNKNOWN_TAG"} = json_response(conn, 200)
    end

    test "401 on bad token", %{conn: conn} do
      conn =
        post(conn, ~p"/api/stations/nope/reads", %{
          "chip_id" => "X",
          "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert json_response(conn, 401)["status"] == "error"
    end

    test "422 on missing chip_id", %{conn: conn, station: station} do
      conn = post(conn, ~p"/api/stations/#{station.token}/reads", %{"rssi" => -10})
      assert json_response(conn, 422)["status"] == "error"
    end
  end

  describe "POST /api/stations/:token/reads/batch" do
    setup [:setup_context]

    test "processes a batch and returns one result per read", %{conn: conn, station: station} do
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      conn =
        post(conn, ~p"/api/stations/#{station.token}/reads/batch", %{
          "reads" => [
            %{"chip_id" => "E200API", "read_at" => now},
            %{"chip_id" => "NOPE", "read_at" => now},
            %{"rssi" => -10}
          ]
        })

      assert %{"results" => [a, b, c]} = json_response(conn, 200)
      assert a["status"] == "recorded"
      assert b["status"] == "unmatched"
      assert c["status"] == "error"
    end

    test "422 on missing reads field", %{conn: conn, station: station} do
      conn = post(conn, ~p"/api/stations/#{station.token}/reads/batch", %{})
      assert json_response(conn, 422)["status"] == "error"
    end
  end

  describe "PUT /api/stations/:token/heartbeat" do
    setup [:setup_context]

    test "stores metadata and updates last_seen_at", %{conn: conn, station: station} do
      conn =
        put(conn, ~p"/api/stations/#{station.token}/heartbeat", %{
          "firmware_version" => "0.3.0",
          "reads_total" => 5,
          "buffer_size" => 0,
          "uptime_seconds" => 10,
          "reader_connected" => true
        })

      assert json_response(conn, 200)["status"] == "ok"

      reloaded = Timing.get_station_by_token(station.token)
      assert reloaded.firmware_version == "0.3.0"
      assert reloaded.status == :online
      assert reloaded.last_seen_at
      assert reloaded.metadata["reads_total"] == 5
    end

    test "401 on bad token", %{conn: conn} do
      conn = put(conn, ~p"/api/stations/nope/heartbeat", %{"reads_total" => 1})
      assert json_response(conn, 401)["status"] == "error"
    end
  end
end
