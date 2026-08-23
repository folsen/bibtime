defmodule Bibtime.Results.Ranker do
  @moduledoc """
  Sorts and assigns rank numbers to a list of `%ParticipantResult{}` structs.
  """

  alias Bibtime.Results.ParticipantResult

  @active_statuses [:registered, :checked_in, :racing, :finished]

  @doc """
  Ranks results overall.

  Participants who recorded the final split are ranked first, on `total_ms`
  alone: a finish read gives the true total even when intermediate checkpoints
  were missed, so a missing mid-race read must not cost someone places.
  Everyone else still on course follows, ordered by `splits_completed`
  descending and then by how quickly they reached that point. DNS/DNF/DSQ
  participants are appended at the end without a meaningful rank.

  Returns the list with the `:rank` field populated.
  """
  def rank_results(results) do
    {active, inactive} = Enum.split_with(results, &(&1.status in @active_statuses))

    sorted_active =
      active
      |> Enum.sort_by(&sort_key/1, :asc)
      |> Enum.with_index(1)
      |> Enum.map(fn {%ParticipantResult{} = r, idx} -> %ParticipantResult{r | rank: idx} end)

    sorted_inactive =
      inactive
      |> Enum.sort_by(fn r -> {status_sort_key(r.status), bib_number(r)} end)

    sorted_active ++ sorted_inactive
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Finishers sort ahead of everyone still on course (leading 0), on total time
  # alone. Those without a final time fall back to progress — furthest along
  # first, then fastest to get there.
  defp sort_key(%ParticipantResult{total_ms: total_ms} = r) when is_integer(total_ms) do
    {0, total_ms, 0, bib_number(r)}
  end

  defp sort_key(%ParticipantResult{} = r) do
    {1, -r.splits_completed, r.last_elapsed_ms || 0, bib_number(r)}
  end

  defp bib_number(%ParticipantResult{participant: p}) do
    case Integer.parse(p.bib_number) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp status_sort_key(:dnf), do: 0
  defp status_sort_key(:dns), do: 1
  defp status_sort_key(:dsq), do: 2
  defp status_sort_key(_), do: 3
end
