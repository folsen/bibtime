defmodule Bibtime.Results.Calculator do
  @moduledoc """
  Computes leg times and builds `%ParticipantResult{}` structs from raw
  split-time data.
  """

  alias Bibtime.Results.ParticipantResult
  alias Bibtime.Participants
  alias Bibtime.Races
  alias Bibtime.Races.AutoCategorizer
  alias Bibtime.Timing

  @doc """
  Calculates results for every participant in the given race.

  Returns a list of `%ParticipantResult{}` structs with leg times and
  totals populated (but without ranking — use `Ranker` for that).
  """
  def calculate_results(race_id) do
    race = Races.get_race!(race_id, preload: [:auto_categories])
    participants = Participants.list_participants(race_id)
    split_times = Timing.get_split_times_for_race(race_id)
    splits = Races.list_splits(race_id)
    auto_categories = race.auto_categories
    split_ids_ordered = Enum.map(splits, & &1.id)
    total_splits = length(split_ids_ordered)

    # Index split times by {participant_id, split_id} for fast lookup
    times_by_participant =
      split_times
      |> Enum.group_by(& &1.participant_id)

    Enum.map(participants, fn participant ->
      participant_times = Map.get(times_by_participant, participant.id, [])

      # Build a map of split_id => elapsed_ms for this participant
      elapsed_by_split =
        participant_times
        |> Enum.into(%{}, fn st -> {st.split_id, st.elapsed_ms} end)

      # Calculate leg times in split order
      {leg_times, _prev_elapsed} =
        Enum.reduce(split_ids_ordered, {%{}, 0}, fn split_id, {acc, prev} ->
          case Map.get(elapsed_by_split, split_id) do
            nil ->
              {acc, prev}

            elapsed ->
              leg = elapsed - prev
              {Map.put(acc, split_id, leg), elapsed}
          end
        end)

      splits_completed = map_size(leg_times)

      # Total time is the elapsed_ms of the last split, but only when every
      # split has been recorded.
      total_ms =
        if splits_completed == total_splits and total_splits > 0 do
          last_split_id = List.last(split_ids_ordered)
          Map.get(elapsed_by_split, last_split_id)
        else
          nil
        end

      matched_auto_cats = AutoCategorizer.match(participant, auto_categories, race.date)

      %ParticipantResult{
        participant: participant,
        category: participant.race_category,
        splits_completed: splits_completed,
        leg_times: leg_times,
        total_ms: total_ms,
        status: participant.status,
        auto_categories: matched_auto_cats
      }
    end)
  end

  @doc """
  Formats a duration in milliseconds as a human-readable string.

  Returns `"HH:MM:SS"` when the duration is one hour or more, or `"MM:SS"`
  otherwise.
  """
  def format_time(nil), do: "--:--"

  def format_time(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    if hours > 0 do
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(minutes) <> ":" <> pad(seconds)
    end
  end

  @doc """
  Formats pace/speed for a leg given time in ms, distance in meters, and display mode.

  Returns `nil` when pace cannot be computed (missing time or distance, or display is `:none`).
  """
  def format_pace(_ms, _distance_meters, :none), do: nil
  def format_pace(nil, _distance_meters, _mode), do: nil
  def format_pace(_ms, nil, _mode), do: nil
  def format_pace(_ms, 0, _mode), do: nil

  def format_pace(ms, distance_meters, :min_per_km) do
    # minutes per kilometer
    km = distance_meters / 1000
    seconds_per_km = ms / 1000 / km
    mins = trunc(seconds_per_km / 60)
    secs = trunc(rem(trunc(seconds_per_km), 60))
    "#{mins}:#{pad(secs)} /km"
  end

  def format_pace(ms, distance_meters, :min_per_100m) do
    # minutes per 100m (swimming)
    hundreds = distance_meters / 100
    seconds_per_100m = ms / 1000 / hundreds
    mins = trunc(seconds_per_100m / 60)
    secs = trunc(rem(trunc(seconds_per_100m), 60))
    "#{mins}:#{pad(secs)} /100m"
  end

  def format_pace(ms, distance_meters, :km_per_h) do
    # kilometers per hour
    hours = ms / 1000 / 3600
    km = distance_meters / 1000
    speed = km / hours
    :erlang.float_to_binary(speed, decimals: 1) <> " km/h"
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
