defmodule Bibtime.ResultsTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Results
  alias Bibtime.Timing
  alias Bibtime.Participants
  alias Bibtime.Races.{Race, RaceCategory, Split}
  alias Bibtime.Participants.Participant

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race! do
    Repo.insert!(%Race{
      name: "Results Race",
      slug: "results-race-#{System.unique_integer([:positive])}",
      race_type: :triathlon,
      status: :in_progress
    })
  end

  defp create_category!(race, name, sort_order) do
    Repo.insert!(%RaceCategory{
      name: name,
      race_id: race.id,
      sort_order: sort_order
    })
  end

  defp create_splits!(race) do
    s1 =
      Repo.insert!(%Split{
        name: "Swim",
        short_name: "swim",
        leg_type: :swim,
        race_id: race.id,
        sort_order: 1
      })

    s2 =
      Repo.insert!(%Split{
        name: "Bike",
        short_name: "bike",
        leg_type: :bike,
        race_id: race.id,
        sort_order: 2
      })

    s3 =
      Repo.insert!(%Split{
        name: "Run",
        short_name: "run",
        leg_type: :run,
        race_id: race.id,
        sort_order: 3
      })

    {s1, s2, s3}
  end

  defp create_participant!(race, bib, first_name, opts \\ %{}) do
    attrs =
      Map.merge(
        %{
          bib_number: bib,
          first_name: first_name,
          last_name: "Test",
          race_id: race.id
        },
        opts
      )

    Repo.insert!(struct(Participant, attrs))
  end

  defp record_time!(participant_id, split_id, elapsed_ms) do
    {:ok, st} =
      Timing.record_split_time(%{
        elapsed_ms: elapsed_ms,
        source: :manual,
        participant_id: participant_id,
        split_id: split_id
      })

    st
  end

  # ---------------------------------------------------------------------------
  # Calculator tests
  # ---------------------------------------------------------------------------

  describe "calculate_results/1 via Results.get_race_results/1" do
    test "returns results for all participants" do
      race = create_race!()
      {_s1, _s2, _s3} = create_splits!(race)
      create_participant!(race, "1", "Alice")
      create_participant!(race, "2", "Bob")

      results = Results.get_race_results(race.id)
      assert length(results) == 2
    end

    test "leg times are correctly calculated" do
      race = create_race!()
      {s1, s2, s3} = create_splits!(race)
      p = create_participant!(race, "1", "Alice")

      # Swim: elapsed 100s, Bike: elapsed 400s, Run: elapsed 900s
      record_time!(p.id, s1.id, 100_000)
      record_time!(p.id, s2.id, 400_000)
      record_time!(p.id, s3.id, 900_000)

      [result] = Results.get_race_results(race.id)

      # First leg = elapsed time (100s)
      assert result.leg_times[s1.id] == 100_000
      # Second leg = 400s - 100s = 300s
      assert result.leg_times[s2.id] == 300_000
      # Third leg = 900s - 400s = 500s
      assert result.leg_times[s3.id] == 500_000
    end

    test "finished participants have total_ms set" do
      race = create_race!()
      {s1, s2, s3} = create_splits!(race)
      p = create_participant!(race, "1", "Alice")

      record_time!(p.id, s1.id, 100_000)
      record_time!(p.id, s2.id, 400_000)
      record_time!(p.id, s3.id, 900_000)

      [result] = Results.get_race_results(race.id)
      assert result.total_ms == 900_000
      assert result.status == :finished
    end

    test "participants with partial splits have correct splits_completed count" do
      race = create_race!()
      {s1, _s2, _s3} = create_splits!(race)
      p = create_participant!(race, "1", "Alice")

      record_time!(p.id, s1.id, 100_000)

      [result] = Results.get_race_results(race.id)
      assert result.splits_completed == 1
      assert result.total_ms == nil
      assert result.status == :racing
    end

    test "DNS/DNF/DSQ participants have correct status" do
      race = create_race!()
      {_s1, _s2, _s3} = create_splits!(race)
      p_dns = create_participant!(race, "1", "DNS")
      p_dnf = create_participant!(race, "2", "DNF")
      p_dsq = create_participant!(race, "3", "DSQ")

      Participants.mark_dns(p_dns)
      Participants.mark_dnf(p_dnf)
      Participants.mark_dsq(p_dsq)

      results = Results.get_race_results(race.id)
      statuses = results |> Enum.map(& &1.status) |> Enum.sort()
      assert :dnf in statuses
      assert :dns in statuses
      assert :dsq in statuses
    end
  end

  # ---------------------------------------------------------------------------
  # Ranker tests
  # ---------------------------------------------------------------------------

  describe "ranking" do
    test "finished participants ranked before partial, partial before DNS" do
      race = create_race!()
      {s1, s2, s3} = create_splits!(race)

      p_finished = create_participant!(race, "1", "Finished")
      p_partial = create_participant!(race, "2", "Partial")
      p_dns = create_participant!(race, "3", "DNS")

      # Finished participant - all splits
      record_time!(p_finished.id, s1.id, 100_000)
      record_time!(p_finished.id, s2.id, 400_000)
      record_time!(p_finished.id, s3.id, 900_000)

      # Partial - only first split
      record_time!(p_partial.id, s1.id, 90_000)

      # DNS
      Participants.mark_dns(p_dns)

      results = Results.get_race_results(race.id)

      ranked = Enum.filter(results, &(&1.rank != nil))
      unranked = Enum.filter(results, &(&1.rank == nil))

      # Finished first (rank 1), then partial (rank 2)
      assert length(ranked) == 2
      finished_result = Enum.find(ranked, &(&1.participant.id == p_finished.id))
      partial_result = Enum.find(ranked, &(&1.participant.id == p_partial.id))

      assert finished_result.rank == 1
      assert partial_result.rank == 2

      # DNS participant has no rank
      assert length(unranked) == 1
      assert hd(unranked).status == :dns
    end

    test "among finished, lower total_ms = better rank" do
      race = create_race!()
      {s1, s2, s3} = create_splits!(race)

      p_fast = create_participant!(race, "1", "Fast")
      p_slow = create_participant!(race, "2", "Slow")

      # Fast finisher
      record_time!(p_fast.id, s1.id, 100_000)
      record_time!(p_fast.id, s2.id, 300_000)
      record_time!(p_fast.id, s3.id, 600_000)

      # Slow finisher
      record_time!(p_slow.id, s1.id, 200_000)
      record_time!(p_slow.id, s2.id, 500_000)
      record_time!(p_slow.id, s3.id, 900_000)

      results = Results.get_race_results(race.id)
      fast_result = Enum.find(results, &(&1.participant.id == p_fast.id))
      slow_result = Enum.find(results, &(&1.participant.id == p_slow.id))

      assert fast_result.rank == 1
      assert slow_result.rank == 2
    end

    test "category ranking works independently" do
      race = create_race!()
      {s1, s2, s3} = create_splits!(race)
      cat_a = create_category!(race, "Elite", 1)
      cat_b = create_category!(race, "Age Group", 2)

      p_a1 = create_participant!(race, "1", "A-Fast", %{race_category_id: cat_a.id})
      p_a2 = create_participant!(race, "2", "A-Slow", %{race_category_id: cat_a.id})
      p_b1 = create_participant!(race, "3", "B-Fast", %{race_category_id: cat_b.id})

      # A-Fast finishes fastest overall
      record_time!(p_a1.id, s1.id, 100_000)
      record_time!(p_a1.id, s2.id, 300_000)
      record_time!(p_a1.id, s3.id, 500_000)

      # B-Fast finishes second overall
      record_time!(p_b1.id, s1.id, 110_000)
      record_time!(p_b1.id, s2.id, 310_000)
      record_time!(p_b1.id, s3.id, 600_000)

      # A-Slow finishes third overall
      record_time!(p_a2.id, s1.id, 200_000)
      record_time!(p_a2.id, s2.id, 500_000)
      record_time!(p_a2.id, s3.id, 900_000)

      results = Results.get_race_results(race.id)

      a1_result = Enum.find(results, &(&1.participant.id == p_a1.id))
      a2_result = Enum.find(results, &(&1.participant.id == p_a2.id))
      b1_result = Enum.find(results, &(&1.participant.id == p_b1.id))

      # Overall: A-Fast=1, B-Fast=2, A-Slow=3
      assert a1_result.rank == 1
      assert b1_result.rank == 2
      assert a2_result.rank == 3

      # Category Elite: A-Fast=1, A-Slow=2
      elite_results = Results.get_category_results(race.id, cat_a.id)
      elite_a1 = Enum.find(elite_results, &(&1.participant.id == p_a1.id))
      elite_a2 = Enum.find(elite_results, &(&1.participant.id == p_a2.id))
      assert elite_a1.rank == 1
      assert elite_a2.rank == 2

      # Category Age Group: B-Fast=1
      age_results = Results.get_category_results(race.id, cat_b.id)
      age_b1 = Enum.find(age_results, &(&1.participant.id == p_b1.id))
      assert age_b1.rank == 1
    end
  end
end
