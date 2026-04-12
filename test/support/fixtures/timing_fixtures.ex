defmodule Bibtime.TimingFixtures do
  @moduledoc """
  Test helpers for creating timing-related entities.
  """

  alias Bibtime.Timing

  def record_split_time!(participant, split, elapsed_ms) do
    {:ok, split_time} =
      Timing.record_split_time(%{
        elapsed_ms: elapsed_ms,
        source: :manual,
        participant_id: participant.id,
        split_id: split.id
      })

    split_time
  end

  def start_race_fixture(race, started_at \\ DateTime.utc_now()) do
    {:ok, race_start} =
      Timing.start_race(%{
        race_id: race.id,
        started_at: started_at
      })

    race_start
  end

  def station_fixture(attrs \\ %{}) do
    attrs = Map.put_new(attrs, "name", "Test Station")

    {:ok, station} = Timing.create_timing_station(attrs)
    station
  end
end
