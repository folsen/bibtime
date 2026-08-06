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
    station = assign_station!(station, swim)

    %{race: race, split: swim, station: station}
  end

  # A station covering both the bike and run splits of a triathlon that
  # started long enough ago that offsets from the gun can be chosen freely.
  defp setup_multi_station(station_attrs \\ %{}) do
    {race, [swim, bike, run]} = triathlon_fixture()

    started_at =
      DateTime.utc_now()
      |> DateTime.add(-4 * 3600, :second)
      |> DateTime.truncate(:second)

    start_race_fixture(race, started_at)

    station =
      station_attrs
      |> Map.put_new("name", "Bike/Run")
      |> station_fixture()
      |> assign_station!(bike)
      |> assign_station!(run)

    %{race: race, swim: swim, bike: bike, run: run, station: station, started_at: started_at}
  end

  defp offset_iso(started_at, seconds) do
    started_at |> DateTime.add(seconds, :second) |> DateTime.to_iso8601()
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
      assert is_binary(payload.participant_name)
      assert %DateTime{} = payload.at
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

  describe "ingest_chip_read/2 with a multi-split station" do
    test "credits the lowest missing split, then the next, then reports duplicate" do
      %{race: race, bike: bike, run: run, station: station, started_at: started_at} =
        setup_multi_station()

      _ = participant_fixture(race, %{chip_id: "E200M1", bib_number: "50"})

      assert {:ok, :recorded, _p, first} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M1",
                 "read_at" => offset_iso(started_at, 600)
               })

      assert first.split_id == bike.id
      refute first.needs_review

      assert {:ok, :recorded, _p, second} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M1",
                 "read_at" => offset_iso(started_at, 600 + 1800)
               })

      assert second.split_id == run.id
      refute second.needs_review

      assert {:ok, :duplicate, _p} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M1",
                 "read_at" => offset_iso(started_at, 600 + 3600)
               })
    end

    test "a re-read within the lockout window is a duplicate, not the next split" do
      %{race: race, station: station, started_at: started_at} = setup_multi_station()

      participant = participant_fixture(race, %{chip_id: "E200M2", bib_number: "51"})

      assert {:ok, :recorded, _p, _st} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M2",
                 "read_at" => offset_iso(started_at, 600)
               })

      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")

      # 60s later — inside the default 120s lockout
      assert {:ok, :duplicate, _p} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M2",
                 "read_at" => offset_iso(started_at, 660)
               })

      assert_receive {:station_read, _station_id, payload}
      assert payload.status == :duplicate
      assert payload.reason == :lockout
      assert payload.seconds_since_last == 60
      assert payload.bib_number == "51"

      assert [only] = Timing.get_split_times_for_participant(participant.id)
      assert only.split.short_name == "bike"
    end

    test "broadcasts an :all_recorded duplicate when every station split is done" do
      %{race: race, bike: bike, run: run, station: station, started_at: started_at} =
        setup_multi_station()

      participant = participant_fixture(race, %{chip_id: "E200M10", bib_number: "59"})
      _ = record_split_time!(participant, bike, 600_000)
      _ = record_split_time!(participant, run, 2_400_000)

      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")

      assert {:ok, :duplicate, _p} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M10",
                 "read_at" => offset_iso(started_at, 3_600)
               })

      assert_receive {:station_read, _station_id, payload}
      assert payload.status == :duplicate
      assert payload.reason == :all_recorded
    end

    test "a lower pass_lockout_seconds allows faster consecutive passes" do
      %{race: race, bike: bike, run: run, station: station, started_at: started_at} =
        setup_multi_station(%{"pass_lockout_seconds" => 30})

      _ = participant_fixture(race, %{chip_id: "E200M3", bib_number: "52"})

      assert {:ok, :recorded, _p, first} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M3",
                 "read_at" => offset_iso(started_at, 600)
               })

      assert first.split_id == bike.id

      assert {:ok, :recorded, _p, second} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M3",
                 "read_at" => offset_iso(started_at, 660)
               })

      assert second.split_id == run.id
    end

    test "lockout applies against manually recorded times with an absolute_time" do
      %{race: race, bike: bike, station: station, started_at: started_at} =
        setup_multi_station()

      participant = participant_fixture(race, %{chip_id: "E200M4", bib_number: "53"})

      manual_at = DateTime.add(started_at, 600, :second)
      _ = record_split_time!(participant, bike, 600_000, %{absolute_time: manual_at})

      assert {:ok, :duplicate, _p} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M4",
                 "read_at" => offset_iso(started_at, 660)
               })
    end

    test "flags an out-of-order backfill for review" do
      %{race: race, bike: bike, run: run, station: station, started_at: started_at} =
        setup_multi_station()

      participant = participant_fixture(race, %{chip_id: "E200M5", bib_number: "54"})

      # Run (a later split) is already recorded; the read backfills bike.
      _ = record_split_time!(participant, run, 10_000_000)

      assert {:ok, :recorded, _p, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M5",
                 "read_at" => offset_iso(started_at, 600)
               })

      assert split_time.split_id == bike.id
      assert split_time.needs_review
    end

    test "flags a statistical outlier against the field" do
      %{race: race, bike: bike, station: station, started_at: started_at} =
        setup_multi_station()

      for n <- 1..5 do
        other = participant_fixture(race, %{chip_id: "E200F#{n}", bib_number: "#{60 + n}"})
        record_split_time!(other, bike, 3_600_000)
      end

      _ = participant_fixture(race, %{chip_id: "E200M6", bib_number: "55"})

      # 9_000_000 ms elapsed — more than double the field median of 3_600_000
      assert {:ok, :recorded, _p, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M6",
                 "read_at" => offset_iso(started_at, 9_000)
               })

      assert split_time.split_id == bike.id
      assert split_time.needs_review
    end

    test "does not flag typical times against the field" do
      %{race: race, bike: bike, station: station, started_at: started_at} =
        setup_multi_station()

      for n <- 1..5 do
        other = participant_fixture(race, %{chip_id: "E200G#{n}", bib_number: "#{70 + n}"})
        record_split_time!(other, bike, 3_600_000)
      end

      _ = participant_fixture(race, %{chip_id: "E200M9", bib_number: "58"})

      # 4_000_000 ms elapsed — comfortably inside [median/2, median*2]
      assert {:ok, :recorded, _p, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M9",
                 "read_at" => offset_iso(started_at, 4_000)
               })

      assert split_time.split_id == bike.id
      refute split_time.needs_review
    end

    test "does not flag when fewer than five field samples exist" do
      %{race: race, bike: bike, station: station, started_at: started_at} =
        setup_multi_station()

      for n <- 1..4 do
        other = participant_fixture(race, %{chip_id: "E200H#{n}", bib_number: "#{80 + n}"})
        record_split_time!(other, bike, 3_600_000)
      end

      _ = participant_fixture(race, %{chip_id: "E200M7", bib_number: "56"})

      assert {:ok, :recorded, _p, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M7",
                 "read_at" => offset_iso(started_at, 20_000)
               })

      refute split_time.needs_review
    end

    test "single-split stations never flag for review" do
      {race, [swim, _bike, run]} = triathlon_fixture()

      started_at =
        DateTime.utc_now()
        |> DateTime.add(-4 * 3600, :second)
        |> DateTime.truncate(:second)

      start_race_fixture(race, started_at)

      station = station_fixture(%{"name" => "Swim Only"}) |> assign_station!(swim)

      participant = participant_fixture(race, %{chip_id: "E200M8", bib_number: "57"})

      # Even with a blatant out-of-order signal (run already recorded)...
      _ = record_split_time!(participant, run, 10_000_000)

      assert {:ok, :recorded, _p, split_time} =
               Timing.ingest_chip_read(station, %{
                 "chip_id" => "E200M8",
                 "read_at" => offset_iso(started_at, 600)
               })

      assert split_time.split_id == swim.id
      refute split_time.needs_review
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
