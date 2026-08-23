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

  describe "missing intermediate splits" do
    test "leg following a missed split is omitted rather than absorbing its time" do
      {race, [swim, bike, run]} = triathlon_fixture()

      p = participant_fixture(race, %{bib_number: "1", first_name: "MissedBike"})

      record_split_time!(p, swim, 1_100_000)
      # No bike read — bike+run would otherwise collapse into the run leg.
      record_split_time!(p, run, 7_000_000)

      [result] = Results.get_race_results(race.id)

      assert Map.get(result.leg_times, swim.id) == 1_100_000
      assert Map.get(result.leg_times, bike.id) == nil
      assert Map.get(result.leg_times, run.id) == nil

      # Total still comes straight off the finish read.
      assert result.total_ms == 7_000_000
      assert result.splits_completed == 2
    end

    test "pace is suppressed for a leg spanning a missed split" do
      race = race_fixture(%{status: :in_progress})

      swim =
        split_fixture(race, %{
          name: "Swim",
          short_name: "swim",
          leg_type: :swim,
          sort_order: 1,
          distance_meters: 1_500,
          pace_display: :min_per_100m
        })

      bike =
        split_fixture(race, %{
          name: "Bike",
          short_name: "bike",
          leg_type: :bike,
          sort_order: 2,
          distance_meters: 40_000,
          pace_display: :km_per_h
        })

      run =
        split_fixture(race, %{
          name: "Run",
          short_name: "run",
          leg_type: :run,
          sort_order: 3,
          distance_meters: 10_000,
          pace_display: :min_per_km
        })

      p = participant_fixture(race, %{bib_number: "1"})
      record_split_time!(p, swim, 1_100_000)
      record_split_time!(p, run, 7_000_000)

      [result] = Results.get_race_results(race.id)

      # The run leg would have reported a plausible-looking 9:50 /km for what
      # was really bike+run.
      for split <- [bike, run] do
        leg = Map.get(result.leg_times, split.id)
        assert Calculator.format_time(leg) == "--:--"
        assert Calculator.format_pace(leg, split.distance_meters, split.pace_display) == nil
      end

      assert Calculator.format_pace(
               Map.get(result.leg_times, swim.id),
               swim.distance_meters,
               swim.pace_display
             ) == "1:13 /100m"
    end

    test "only a finish read still yields the correct total" do
      {race, [swim, bike, run]} = triathlon_fixture()

      p = participant_fixture(race, %{bib_number: "1", first_name: "FinishOnly"})
      record_split_time!(p, run, 6_000_000)

      [result] = Results.get_race_results(race.id)

      assert result.total_ms == 6_000_000
      assert result.splits_completed == 1

      # Every leg column reads "--:--" — the run leg would otherwise have
      # reported the entire race as a run time.
      for split <- [swim, bike, run] do
        assert Map.get(result.leg_times, split.id) == nil
      end
    end
  end

  describe "ranking finishers with missing splits" do
    test "a faster finisher outranks a slower one with more splits recorded" do
      {race, [swim, bike, run]} = triathlon_fixture()

      complete = participant_fixture(race, %{bib_number: "1", first_name: "Complete"})
      record_split_time!(complete, swim, 1_200_000)
      record_split_time!(complete, bike, 5_400_000)
      record_split_time!(complete, run, 8_000_000)

      missed = participant_fixture(race, %{bib_number: "2", first_name: "MissedBike"})
      record_split_time!(missed, swim, 1_100_000)
      record_split_time!(missed, run, 7_000_000)

      results = Results.get_race_results(race.id)

      r_missed = Enum.find(results, &(&1.participant.id == missed.id))
      r_complete = Enum.find(results, &(&1.participant.id == complete.id))

      assert r_missed.rank == 1
      assert r_complete.rank == 2
    end

    test "a finisher outranks someone still on course with more splits recorded" do
      {race, [swim, bike, run]} = triathlon_fixture()

      finisher = participant_fixture(race, %{bib_number: "1", first_name: "FinishOnly"})
      record_split_time!(finisher, run, 8_000_000)

      racing = participant_fixture(race, %{bib_number: "2", first_name: "StillRacing"})
      record_split_time!(racing, swim, 1_000_000)
      record_split_time!(racing, bike, 5_000_000)

      results = Results.get_race_results(race.id)

      r_finisher = Enum.find(results, &(&1.participant.id == finisher.id))
      r_racing = Enum.find(results, &(&1.participant.id == racing.id))

      assert r_finisher.splits_completed < r_racing.splits_completed
      assert r_finisher.rank == 1
      assert r_racing.rank == 2
    end

    test "participants still on course are ordered by progress, then elapsed" do
      {race, [swim, bike, _run]} = triathlon_fixture()

      ahead = participant_fixture(race, %{bib_number: "1", first_name: "Ahead"})
      record_split_time!(ahead, swim, 2_000_000)
      record_split_time!(ahead, bike, 5_000_000)

      fast_swim = participant_fixture(race, %{bib_number: "2", first_name: "FastSwim"})
      record_split_time!(fast_swim, swim, 500_000)

      slow_swim = participant_fixture(race, %{bib_number: "3", first_name: "SlowSwim"})
      record_split_time!(slow_swim, swim, 900_000)

      results = Results.get_race_results(race.id)
      order = results |> Enum.sort_by(& &1.rank) |> Enum.map(& &1.participant.first_name)

      assert order == ["Ahead", "FastSwim", "SlowSwim"]
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
