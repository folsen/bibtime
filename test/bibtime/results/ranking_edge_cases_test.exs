defmodule Bibtime.Results.RankingEdgeCasesTest do
  use Bibtime.DataCase, async: true

  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.TimingFixtures

  alias Bibtime.Results
  alias Bibtime.Results.Calculator

  describe "tied finish times" do
    test "participants with identical total_ms both get sequential ranks" do
      {race, [swim, bike, run]} = triathlon_fixture()

      p1 = participant_fixture(race, %{bib_number: "1", first_name: "Alice"})
      p2 = participant_fixture(race, %{bib_number: "2", first_name: "Bob"})

      # Both finish with exactly 600_000ms total
      record_split_time!(p1, swim, 100_000)
      record_split_time!(p1, bike, 300_000)
      record_split_time!(p1, run, 600_000)

      record_split_time!(p2, swim, 200_000)
      record_split_time!(p2, bike, 400_000)
      record_split_time!(p2, run, 600_000)

      results = Results.get_race_results(race.id)

      p1_result = Enum.find(results, &(&1.participant.id == p1.id))
      p2_result = Enum.find(results, &(&1.participant.id == p2.id))

      # Both should be ranked (exact behavior: tiebreak by bib number)
      assert p1_result.rank != nil
      assert p2_result.rank != nil
      assert p1_result.total_ms == p2_result.total_ms

      # Lower bib number gets better rank as tiebreaker
      assert p1_result.rank < p2_result.rank
    end

    test "three-way tie assigns sequential ranks by bib number" do
      {race, [swim, bike, run]} = triathlon_fixture()

      p1 = participant_fixture(race, %{bib_number: "10", first_name: "A"})
      p2 = participant_fixture(race, %{bib_number: "20", first_name: "B"})
      p3 = participant_fixture(race, %{bib_number: "30", first_name: "C"})

      for p <- [p1, p2, p3] do
        record_split_time!(p, swim, 100_000)
        record_split_time!(p, bike, 300_000)
        record_split_time!(p, run, 500_000)
      end

      results = Results.get_race_results(race.id)
      ranks = results |> Enum.sort_by(& &1.rank) |> Enum.map(& &1.rank)

      assert ranks == [1, 2, 3]
    end
  end

  describe "race with zero splits" do
    test "all participants have nil total_ms and status from participant record" do
      race = race_fixture(%{status: :in_progress})
      # No splits created
      p1 = participant_fixture(race, %{bib_number: "1"})
      _p2 = participant_fixture(race, %{bib_number: "2"})

      results = Results.get_race_results(race.id)

      assert length(results) == 2

      r1 = Enum.find(results, &(&1.participant.id == p1.id))
      assert r1.total_ms == nil
      assert r1.splits_completed == 0
    end
  end

  describe "partial progress ranking" do
    test "participant with more splits_completed ranks higher even with slower pace" do
      {race, [swim, bike, _run]} = triathlon_fixture()

      p_2splits = participant_fixture(race, %{bib_number: "1", first_name: "TwoSplits"})
      p_1split = participant_fixture(race, %{bib_number: "2", first_name: "OneSplit"})

      # p_2splits: 2 splits done (slow)
      record_split_time!(p_2splits, swim, 200_000)
      record_split_time!(p_2splits, bike, 500_000)

      # p_1split: 1 split done (fast)
      record_split_time!(p_1split, swim, 50_000)

      results = Results.get_race_results(race.id)

      r_2splits = Enum.find(results, &(&1.participant.id == p_2splits.id))
      r_1split = Enum.find(results, &(&1.participant.id == p_1split.id))

      assert r_2splits.rank < r_1split.rank
    end
  end

  describe "Calculator.format_time/1" do
    test "nil returns placeholder" do
      assert Calculator.format_time(nil) == "--:--"
    end

    test "formats sub-hour times as MM:SS" do
      # 5 minutes, 30 seconds = 330_000ms
      assert Calculator.format_time(330_000) == "05:30"
    end

    test "formats exactly one hour" do
      # 1 hour = 3_600_000ms
      assert Calculator.format_time(3_600_000) == "01:00:00"
    end

    test "formats multi-hour times" do
      # 2 hours, 15 minutes, 45 seconds
      ms = (2 * 3600 + 15 * 60 + 45) * 1000
      assert Calculator.format_time(ms) == "02:15:45"
    end

    test "formats zero" do
      assert Calculator.format_time(0) == "00:00"
    end

    test "formats single-digit seconds" do
      # 1 minute, 5 seconds
      assert Calculator.format_time(65_000) == "01:05"
    end

    test "truncates sub-second precision" do
      # 5 minutes, 30 seconds and 999ms
      assert Calculator.format_time(330_999) == "05:30"
    end

    test "formats large times correctly" do
      # 12 hours, 0 minutes, 0 seconds
      ms = 12 * 3600 * 1000
      assert Calculator.format_time(ms) == "12:00:00"
    end
  end
end
