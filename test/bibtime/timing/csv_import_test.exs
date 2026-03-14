defmodule Bibtime.Timing.CSVImportTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Timing.CSVImport
  alias Bibtime.Timing
  alias Bibtime.Races.{Race, Split}
  alias Bibtime.Participants.Participant

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race! do
    Repo.insert!(%Race{
      name: "CSV Import Race",
      slug: "csv-race-#{System.unique_integer([:positive])}",
      race_type: :running,
      status: :in_progress
    })
  end

  defp create_split!(race, short_name, sort_order) do
    Repo.insert!(%Split{
      name: "Split #{short_name}",
      short_name: short_name,
      leg_type: :run,
      race_id: race.id,
      sort_order: sort_order
    })
  end

  defp create_participant!(race, bib_number) do
    Repo.insert!(%Participant{
      bib_number: bib_number,
      first_name: "Runner",
      last_name: "#{bib_number}",
      race_id: race.id
    })
  end

  # ---------------------------------------------------------------------------
  # parse/1
  # ---------------------------------------------------------------------------

  describe "parse/1" do
    test "parses valid CSV and returns rows" do
      csv = """
      bib_number,split_short_name,elapsed_time
      101,swim,00:15:30
      102,swim,00:16:00
      """

      assert {:ok, rows} = CSVImport.parse(csv)
      assert length(rows) == 2
      assert hd(rows).bib_number == "101"
      assert hd(rows).split_short_name == "swim"
      assert hd(rows).elapsed_time == "00:15:30"
    end

    test "returns error for CSV with wrong column count" do
      csv = """
      bib_number,split_short_name,elapsed_time
      101,swim
      102
      """

      assert {:error, errors} = CSVImport.parse(csv)
      assert length(errors) == 2
      assert Enum.all?(errors, &(&1.field == "csv"))
      assert Enum.all?(errors, &String.contains?(&1.message, "at least 3 columns"))
    end

    test "returns error for empty CSV" do
      assert {:error, [%{row: 0, field: "csv", message: "CSV is empty"}]} = CSVImport.parse("")
    end
  end

  # ---------------------------------------------------------------------------
  # validate/2
  # ---------------------------------------------------------------------------

  describe "validate/2" do
    test "with valid data succeeds" do
      race = create_race!()
      create_split!(race, "swim", 1)
      create_participant!(race, "101")

      rows = [%{bib_number: "101", split_short_name: "swim", elapsed_time: "00:15:30"}]
      assert {:ok, validated} = CSVImport.validate(rows, race.id)
      assert length(validated) == 1
      assert hd(validated).elapsed_ms == 930_000
      assert hd(validated).source == :import
    end

    test "with unknown bib number returns error" do
      race = create_race!()
      create_split!(race, "swim", 1)

      rows = [%{bib_number: "999", split_short_name: "swim", elapsed_time: "00:15:30"}]
      assert {:error, errors} = CSVImport.validate(rows, race.id)
      assert Enum.any?(errors, &(&1.field == "bib_number"))
      assert Enum.any?(errors, &String.contains?(&1.message, "999"))
    end

    test "with unknown split name returns error" do
      race = create_race!()
      create_participant!(race, "101")

      rows = [%{bib_number: "101", split_short_name: "nonexistent", elapsed_time: "00:15:30"}]
      assert {:error, errors} = CSVImport.validate(rows, race.id)
      assert Enum.any?(errors, &(&1.field == "split_short_name"))
      assert Enum.any?(errors, &String.contains?(&1.message, "nonexistent"))
    end
  end

  # ---------------------------------------------------------------------------
  # parse_time/1
  # ---------------------------------------------------------------------------

  describe "parse_time/1" do
    test "handles HH:MM:SS format" do
      assert {:ok, ms} = CSVImport.parse_time("01:30:45")
      # 1*3600 + 30*60 + 45 = 5445 seconds = 5_445_000 ms
      assert ms == 5_445_000
    end

    test "handles MM:SS format" do
      assert {:ok, ms} = CSVImport.parse_time("15:30")
      # 15*60 + 30 = 930 seconds = 930_000 ms
      assert ms == 930_000
    end

    test "handles HH:MM:SS.mmm format with milliseconds" do
      assert {:ok, ms} = CSVImport.parse_time("00:15:30.500")
      # 15*60 + 30 = 930 seconds = 930_000 ms + 500 ms = 930_500
      assert ms == 930_500
    end

    test "handles plain integer milliseconds" do
      assert {:ok, 930_500} = CSVImport.parse_time("930500")
    end

    test "returns error for invalid format" do
      assert :error = CSVImport.parse_time("not-a-time")
    end

    test "handles fractional seconds with fewer than 3 digits" do
      # .5 should be padded to .500
      assert {:ok, ms} = CSVImport.parse_time("00:00:01.5")
      assert ms == 1_500
    end

    test "handles fractional seconds with more than 3 digits" do
      # .1234 should be trimmed to .123
      assert {:ok, ms} = CSVImport.parse_time("00:00:01.1234")
      assert ms == 1_123
    end
  end

  # ---------------------------------------------------------------------------
  # import/2
  # ---------------------------------------------------------------------------

  describe "import/2" do
    test "with valid CSV creates split times" do
      race = create_race!()
      split = create_split!(race, "swim", 1)
      p1 = create_participant!(race, "101")
      p2 = create_participant!(race, "102")

      csv = """
      bib_number,split_short_name,elapsed_time
      101,swim,00:15:30
      102,swim,00:16:00
      """

      assert {:ok, %{imported: 2}} = CSVImport.import(csv, race.id)

      # Verify split times were actually created
      times = Timing.get_split_times_for_race(race.id)
      assert length(times) == 2

      p1_time = Enum.find(times, &(&1.participant_id == p1.id))
      p2_time = Enum.find(times, &(&1.participant_id == p2.id))

      assert p1_time.elapsed_ms == 930_000
      assert p1_time.split_id == split.id
      assert p1_time.source == :import
      assert p2_time.elapsed_ms == 960_000
    end

    test "with invalid CSV returns parse error" do
      race = create_race!()

      csv = """
      bib_number,split_short_name,elapsed_time
      only_one_col
      """

      assert {:error, _errors} = CSVImport.import(csv, race.id)
    end

    test "with unknown bib returns validation error" do
      race = create_race!()
      create_split!(race, "swim", 1)

      csv = """
      bib_number,split_short_name,elapsed_time
      999,swim,00:15:30
      """

      assert {:error, errors} = CSVImport.import(csv, race.id)
      assert is_list(errors)
    end
  end
end
