defmodule Bibtime.Results.Accolades do
  @moduledoc """
  Race highlights — who was fastest at what.

  Computed from a list of `ParticipantResult` structs, so the caller decides
  the field: pass the whole race for race-wide accolades, or a filtered
  category for that category's.

  Only finished participants are considered. A DNF may well have posted a
  quick leg before pulling out, but crediting them with "Fastest Bike" against
  people who completed the course reads wrong on a results board.
  """

  alias Bibtime.Results.Calculator

  @leg_types [:swim, :bike, :run]

  @doc """
  Returns the accolade list, in display order: one per timed leg, then the
  fastest woman and man overall. Legs nobody completed are omitted.
  """
  def compute(results, splits) do
    finished = Enum.filter(results, &(&1.status == :finished))

    if finished == [] do
      []
    else
      leg_accolades(finished, splits) ++ gender_accolades(finished)
    end
  end

  @doc """
  Fastest leg time per split, as `%{split_id => milliseconds}`.

  Drives the highlighting in the results table, so it uses the same
  finished-only rule as `compute/2` — a highlighted cell and an accolade card
  must never disagree about who was fastest.
  """
  def fastest_leg_times(results, splits) do
    finished = Enum.filter(results, &(&1.status == :finished))

    splits
    |> Enum.flat_map(fn split ->
      case fastest_leg_ms(finished, split) do
        nil -> []
        ms -> [{split.id, ms}]
      end
    end)
    |> Map.new()
  end

  @doc """
  The winning total time in milliseconds, or nil when nobody has finished.
  """
  def fastest_total_ms(results) do
    results
    |> Enum.filter(&(&1.status == :finished and &1.total_ms != nil))
    |> Enum.map(& &1.total_ms)
    |> case do
      [] -> nil
      totals -> Enum.min(totals)
    end
  end

  defp leg_accolades(finished, splits) do
    splits
    |> Enum.filter(&(&1.leg_type in @leg_types))
    |> Enum.flat_map(fn split ->
      case fastest_for_split(finished, split) do
        nil -> []
        accolade -> [accolade]
      end
    end)
  end

  defp gender_accolades(finished) do
    Enum.flat_map([:female, :male], fn gender ->
      case fastest_by_gender(finished, gender) do
        nil -> []
        accolade -> [accolade]
      end
    end)
  end

  defp fastest_leg_ms(results, split) do
    results
    |> Enum.map(&Map.get(&1.leg_times, split.id))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      times -> Enum.min(times)
    end
  end

  defp fastest_for_split(results, split) do
    results
    |> Enum.filter(fn r -> Map.get(r.leg_times, split.id) != nil end)
    |> Enum.min_by(fn r -> Map.get(r.leg_times, split.id) end, fn -> nil end)
    |> case do
      nil ->
        nil

      result ->
        %{
          kind: {:leg, split.leg_type},
          emoji: leg_emoji(split.leg_type),
          label: leg_label(split.leg_type),
          participant: result.participant,
          detail: Calculator.format_time(Map.get(result.leg_times, split.id))
        }
    end
  end

  defp fastest_by_gender(results, gender) do
    results
    |> Enum.filter(fn r -> r.participant.gender == gender and r.total_ms != nil end)
    |> Enum.min_by(& &1.total_ms, fn -> nil end)
    |> case do
      nil ->
        nil

      result ->
        %{
          kind: {:overall, gender},
          emoji: "\u{1F3C6}",
          label: gender_label(gender),
          participant: result.participant,
          detail: Calculator.format_time(result.total_ms)
        }
    end
  end

  # Labels are resolved by the caller so they render in the viewer's locale
  # rather than whichever one happened to be active when the list was built.
  defp leg_label(:swim), do: :fastest_swim
  defp leg_label(:bike), do: :fastest_bike
  defp leg_label(:run), do: :fastest_run

  defp gender_label(:female), do: :fastest_woman
  defp gender_label(:male), do: :fastest_man

  defp leg_emoji(:swim), do: "\u{1F3CA}"
  defp leg_emoji(:bike), do: "\u{1F6B4}"
  defp leg_emoji(:run), do: "\u{1F3C3}"
end
