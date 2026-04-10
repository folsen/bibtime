defmodule Bibtime.Results.Ranker do
  @moduledoc """
  Sorts and assigns rank numbers to a list of `%ParticipantResult{}` structs.
  """

  alias Bibtime.Results.ParticipantResult

  @active_statuses [:registered, :checked_in, :racing, :finished]

  @doc """
  Ranks results overall.

  Active participants (`:racing` or `:finished`) are ranked first — sorted by
  `splits_completed` descending, then by `total_ms` (or the last recorded
  split elapsed time) ascending. DNS/DNF/DSQ participants are appended at the
  end without a meaningful rank.

  Returns the list with the `:rank` field populated.
  """
  def rank_results(results) do
    {active, inactive} = Enum.split_with(results, &(&1.status in @active_statuses))

    sorted_active =
      active
      |> Enum.sort_by(
        fn r -> {-r.splits_completed, r.total_ms || max_elapsed(r), bib_number(r)} end,
        :asc
      )
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

  # When total_ms is nil (participant hasn't finished), we fall back to the
  # maximum elapsed time among their recorded leg times so that we can still
  # sort partially-completed participants.
  defp max_elapsed(%ParticipantResult{leg_times: legs}) when map_size(legs) == 0, do: 0

  defp max_elapsed(%ParticipantResult{leg_times: legs}) do
    legs |> Map.values() |> Enum.sum()
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
