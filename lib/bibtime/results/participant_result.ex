defmodule Bibtime.Results.ParticipantResult do
  @moduledoc """
  A struct representing a calculated result for a single participant.

  This is not an Ecto schema — it is built in-memory by the calculator
  and decorated with ranking information by the ranker.
  """

  defstruct [
    :participant,
    :category,
    :splits_completed,
    :leg_times,
    :total_ms,
    :rank,
    :status,
    auto_categories: []
  ]
end
