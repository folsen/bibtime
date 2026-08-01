defmodule Bibtime.TimingFixtures do
  @moduledoc """
  Test helpers for creating timing-related entities.
  """

  alias Bibtime.Timing

  def record_split_time!(participant, split, elapsed_ms, attrs \\ %{}) do
    {:ok, split_time} =
      %{
        elapsed_ms: elapsed_ms,
        source: :manual,
        participant_id: participant.id,
        split_id: split.id
      }
      |> Map.merge(attrs)
      |> Timing.record_split_time()

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

  def assign_station!(station, split) do
    {:ok, _assignment} = Timing.assign_station(station, split)
    station
  end
end
