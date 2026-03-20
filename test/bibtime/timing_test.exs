defmodule Bibtime.TimingTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Timing
  alias Bibtime.Timing.{SplitTime, RaceStart}
  alias Bibtime.Races.{Race, Split}
  alias Bibtime.Participants.Participant

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race! do
    Repo.insert!(%Race{
      name: "Timing Test Race",
      slug: "timing-race-#{System.unique_integer([:positive])}",
      race_type: :triathlon,
      status: :in_progress
    })
  end

  defp create_split!(race, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Split #{System.unique_integer([:positive])}",
          short_name: "s#{System.unique_integer([:positive])}",
          leg_type: :run,
          race_id: race.id,
          sort_order: 0
        },
        overrides
      )

    Repo.insert!(struct(Split, attrs))
  end

  defp create_participant!(race, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          bib_number: "#{System.unique_integer([:positive])}",
          first_name: "Test",
          last_name: "Runner",
          race_id: race.id
        },
        overrides
      )

    Repo.insert!(struct(Participant, attrs))
  end

  # ---------------------------------------------------------------------------
  # SplitTime
  # ---------------------------------------------------------------------------

  describe "record_split_time/1" do
    test "creates a split time" do
      race = create_race!()
      split = create_split!(race)
      participant = create_participant!(race)

      assert {:ok, %SplitTime{} = st} =
               Timing.record_split_time(%{
                 elapsed_ms: 930_500,
                 source: :manual,
                 participant_id: participant.id,
                 split_id: split.id
               })

      assert st.elapsed_ms == 930_500
      assert st.source == :manual
      assert st.participant_id == participant.id
      assert st.split_id == split.id
    end

    test "broadcasts via PubSub" do
      race = create_race!()
      split = create_split!(race)
      participant = create_participant!(race)

      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")

      {:ok, split_time} =
        Timing.record_split_time(%{
          elapsed_ms: 100_000,
          source: :manual,
          participant_id: participant.id,
          split_id: split.id
        })

      assert_receive {:split_time_recorded, ^split_time}
    end

    test "duplicate participant+split fails with unique constraint" do
      race = create_race!()
      split = create_split!(race)
      participant = create_participant!(race)

      attrs = %{
        elapsed_ms: 100_000,
        source: :manual,
        participant_id: participant.id,
        split_id: split.id
      }

      assert {:ok, _} = Timing.record_split_time(attrs)
      assert {:error, changeset} = Timing.record_split_time(attrs)
      assert %{participant_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "delete_split_time/1" do
    test "removes split time and broadcasts" do
      race = create_race!()
      split = create_split!(race)
      participant = create_participant!(race)

      {:ok, st} =
        Timing.record_split_time(%{
          elapsed_ms: 200_000,
          source: :manual,
          participant_id: participant.id,
          split_id: split.id
        })

      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")

      assert {:ok, deleted} = Timing.delete_split_time(st)
      assert deleted.id == st.id
      assert_receive {:split_time_deleted, ^deleted}

      assert_raise Ecto.NoResultsError, fn ->
        Timing.get_split_time!(st.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # RaceStart
  # ---------------------------------------------------------------------------

  describe "start_race/1" do
    test "creates a race start" do
      race = create_race!()
      now = DateTime.utc_now()

      assert {:ok, %RaceStart{} = rs} =
               Timing.start_race(%{
                 started_at: now,
                 race_id: race.id
               })

      assert rs.race_id == race.id
    end
  end

  describe "get_race_start/1" do
    test "returns earliest start when multiple exist" do
      race = create_race!()
      early = ~U[2026-06-01 08:00:00.000000Z]
      late = ~U[2026-06-01 08:30:00.000000Z]

      Timing.start_race(%{started_at: late, race_id: race.id, wave_name: "Wave 2"})
      Timing.start_race(%{started_at: early, race_id: race.id, wave_name: "Wave 1"})

      rs = Timing.get_race_start(race.id)
      assert rs.wave_name == "Wave 1"
      assert DateTime.compare(rs.started_at, early) == :eq
    end

    test "returns nil when no start exists" do
      race = create_race!()
      assert Timing.get_race_start(race.id) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # get_split_times_for_race
  # ---------------------------------------------------------------------------

  describe "get_split_times_for_race/1" do
    test "returns all split times for a race with preloaded associations" do
      race = create_race!()
      split1 = create_split!(race, %{sort_order: 1})
      split2 = create_split!(race, %{sort_order: 2})
      p1 = create_participant!(race)
      p2 = create_participant!(race)

      Timing.record_split_time(%{
        elapsed_ms: 100_000,
        source: :manual,
        participant_id: p1.id,
        split_id: split1.id
      })

      Timing.record_split_time(%{
        elapsed_ms: 200_000,
        source: :manual,
        participant_id: p1.id,
        split_id: split2.id
      })

      Timing.record_split_time(%{
        elapsed_ms: 110_000,
        source: :manual,
        participant_id: p2.id,
        split_id: split1.id
      })

      times = Timing.get_split_times_for_race(race.id)
      assert length(times) == 3

      # Verify preloads
      Enum.each(times, fn st ->
        assert %Participant{} = st.participant
        assert %Split{} = st.split
      end)
    end

    test "does not include split times from other races" do
      race1 = create_race!()
      race2 = create_race!()
      split1 = create_split!(race1)
      split2 = create_split!(race2)
      p1 = create_participant!(race1)
      p2 = create_participant!(race2)

      Timing.record_split_time(%{
        elapsed_ms: 100_000,
        source: :manual,
        participant_id: p1.id,
        split_id: split1.id
      })

      Timing.record_split_time(%{
        elapsed_ms: 200_000,
        source: :manual,
        participant_id: p2.id,
        split_id: split2.id
      })

      times = Timing.get_split_times_for_race(race1.id)
      assert length(times) == 1
      assert hd(times).participant_id == p1.id
    end
  end
end
