defmodule Bibtime.Results do
  @moduledoc """
  The Results context.

  Provides a high-level API for computing and retrieving race results by
  delegating to the Calculator and Ranker modules.
  """

  alias Bibtime.Results.Calculator
  alias Bibtime.Results.Ranker

  @doc """
  Returns a fully ranked list of `%ParticipantResult{}` structs for the
  given race.

  Results are calculated from raw split times, ranked overall, and ranked
  within each category.
  """
  def get_race_results(race_id) do
    race_id
    |> Calculator.calculate_results()
    |> Ranker.rank_results()
  end

  @doc """
  Returns ranked results filtered to the given category.

  Category ranks reflect positions within that specific category.
  """
  def get_category_results(race_id, category_id) do
    race_id
    |> get_race_results()
    |> Enum.filter(fn r -> r.category != nil and r.category.id == category_id end)
    |> Ranker.rank_results()
  end
end
