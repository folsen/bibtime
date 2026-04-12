defmodule Bibtime.Timing.IngestChipReadTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Timing

  import Bibtime.ParticipantsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.TimingFixtures

  defp setup_station(opts \\ []) do
    {race, [swim, _bike, _run]} = triathlon_fixture()

    started? = Keyword.get(opts, :started, true)

    if started? do
      started_at =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      start_race_fixture(race, started_at)
    end

    station = station_fixture(%{"name" => "Swim In"})
    {:ok, station} = Timing.assign_station(station, swim)

    %{race: race, split: swim, station: station}
  end

  describe "ingest_chip_read/2" do
    test "records a split time when the chip matches a participant" do
      %{race: race, split: split, station: station} = setup_station()

      participant = participant_fixture(race, %{chip_id: "E200AA", bib_number: "10"})

      read_at =
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      assert {:ok, :recorded, recorded_participant, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200AA",
                 "read_at" => read_at,
                 "rssi" => -45
               })

      assert recorded_participant.id == participant.id
      assert split_time.participant_id == participant.id
      assert split_time.split_id == split.id
      assert split_time.source == :chip
      assert split_time.elapsed_ms > 0
      assert is_binary(split_time.raw_chip_data)
    end

    test "returns duplicate when a split time already exists for that split" do
      %{race: race, split: split, station: station} = setup_station()
      participant = participant_fixture(race, %{chip_id: "E200BB", bib_number: "20"})
      _ = record_split_time!(participant, split, 1_000)

      assert {:ok, :duplicate, returned} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200BB",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })

      assert returned.id == participant.id
    end

    test "returns unmatched when no participant has that chip" do
      %{station: station} = setup_station()

      assert {:ok, :unmatched} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200ZZ",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })
    end

    test "returns race_not_started when the race has no RaceStart" do
      %{race: race, station: station} = setup_station(started: false)
      _ = participant_fixture(race, %{chip_id: "E200CC", bib_number: "30"})

      assert {:error, :race_not_started} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200CC",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })
    end

    test "returns station_unassigned when station has no split assignment" do
      station = station_fixture(%{"name" => "Orphan"})

      assert {:error, :station_unassigned} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200XX",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })
    end

    test "broadcasts a :station_read message for recorded reads" do
      %{race: race, station: station} = setup_station()
      _ = participant_fixture(race, %{chip_id: "E200DD", bib_number: "40"})

      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")

      assert {:ok, :recorded, _p, _st} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200DD",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })

      assert_receive {:station_read, station_id, payload}
      assert station_id == station.id
      assert payload.status == :recorded
      assert payload.bib_number == "40"
    end

    test "broadcasts a :station_read message for unmatched reads" do
      %{race: race, station: station} = setup_station()
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")

      assert {:ok, :unmatched} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200NOPE",
                 "read_at" => DateTime.utc_now() |> DateTime.to_iso8601()
               })

      assert_receive {:station_read, _station_id, %{status: :unmatched, chip_id: "E200NOPE"}}
    end
  end

  describe "update_station_heartbeat/2" do
    test "merges metadata, updates last_seen_at and broadcasts" do
      %{race: race, station: station} = setup_station()
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")

      {:ok, updated} =
        Timing.update_station_heartbeat(station, %{
          "firmware_version" => "0.2.0",
          "reads_total" => 42,
          "buffer_size" => 0,
          "uptime_seconds" => 120
        })

      assert updated.firmware_version == "0.2.0"
      assert updated.status == :online
      assert updated.metadata["reads_total"] == 42
      assert updated.last_seen_at

      assert_receive {:station_heartbeat, station_id, _metadata}
      assert station_id == station.id
    end

    test "does not broadcast when station is unassigned" do
      station = station_fixture(%{"name" => "Unassigned"})

      {:ok, updated} =
        Timing.update_station_heartbeat(station, %{
          "firmware_version" => "0.1.0"
        })

      assert updated.status == :online
      refute_receive {:station_heartbeat, _, _}
    end
  end
end
