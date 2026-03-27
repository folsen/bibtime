defmodule Bibtime.Results do
  @moduledoc """
  The Results context.

  Provides a high-level API for computing and retrieving race results by
  delegating to the Calculator and Ranker modules.
  """

  import Ecto.Query

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
  Returns ranked results filtered to the given manual category.

  Category ranks reflect positions within that specific category.
  """
  def get_category_results(race_id, category_id) do
    race_id
    |> get_race_results()
    |> Enum.filter(fn r -> r.category != nil and r.category.id == category_id end)
    |> Ranker.rank_results()
  end

  @doc """
  Returns ranked results filtered to the given auto category.

  Participants are included if they match the auto category.
  """
  def get_auto_category_results(race_id, auto_category_id) do
    race_id
    |> get_race_results()
    |> Enum.filter(fn r ->
      Enum.any?(r.auto_categories, &(&1.id == auto_category_id))
    end)
    |> Ranker.rank_results()
  end

  @doc """
  Returns a list of race result summaries for every race a user has participated in.

  Each entry is a map with:
    - `:race` — the `%Race{}` struct (with splits preloaded)
    - `:splits` — ordered list of splits for the race
    - `:result` — the user's `%ParticipantResult{}` with overall rank
    - `:category_rank` — rank within their manual category (or nil)
  """
  def get_user_race_results(user_id) do
    alias Bibtime.Participants
    alias Bibtime.Races
    alias Bibtime.Repo

    participants = Participants.list_participants_for_user(user_id)
    race_ids = participants |> Enum.map(& &1.race_id) |> Enum.uniq()

    # Batch-fetch all races with full preloads (1 query instead of N)
    races_by_id =
      Races.Race
      |> where([r], r.id in ^race_ids)
      |> Repo.all()
      |> Repo.preload([:categories, :auto_categories, :splits])
      |> Map.new(fn race -> {race.id, race} end)

    # Batch-fetch all splits grouped by race_id (1 query instead of N)
    splits_by_race_id =
      Races.Split
      |> where([s], s.race_id in ^race_ids)
      |> order_by(:sort_order)
      |> Repo.all()
      |> Enum.group_by(& &1.race_id)

    # Compute results once per unique race (avoiding duplicate expensive calculations)
    results_by_race_id = Map.new(race_ids, fn race_id -> {race_id, get_race_results(race_id)} end)

    Enum.map(participants, fn participant ->
      race = Map.fetch!(races_by_id, participant.race_id)
      splits = Map.get(splits_by_race_id, race.id, [])
      all_results = Map.fetch!(results_by_race_id, race.id)

      result = Enum.find(all_results, fn r -> r.participant.id == participant.id end)

      category_rank =
        if result && result.category do
          category_results =
            all_results
            |> Enum.filter(fn r -> r.category != nil and r.category.id == result.category.id end)
            |> Ranker.rank_results()

          cat_result = Enum.find(category_results, fn r -> r.participant.id == participant.id end)
          if cat_result, do: cat_result.rank
        end

      %{
        participant: participant,
        race: race,
        splits: splits,
        result: result,
        category_rank: category_rank
      }
    end)
    |> Enum.sort_by(fn entry -> entry.race.date end, {:desc, Date})
  end

  @doc """
  Returns ranking information for a specific participant across all categories in a race.

  Returns a map with:
    - `:overall` — `%{rank: integer | nil, total: integer}`
    - `:category` — `%{category: %RaceCategory{}, rank: integer | nil, total: integer}` or nil
    - `:auto_categories` — list of `%{auto_category: %RaceAutoCategory{}, rank: integer | nil, total: integer}`
  """
  def get_participant_rankings(race_id, participant_id) do
    alias Bibtime.Races

    all_results = get_race_results(race_id)
    result = Enum.find(all_results, fn r -> r.participant.id == participant_id end)

    overall = %{rank: if(result, do: result.rank), total: length(all_results)}

    category =
      if result && result.category do
        cat_results =
          all_results
          |> Enum.filter(fn r -> r.category != nil and r.category.id == result.category.id end)
          |> Ranker.rank_results()

        cat_result = Enum.find(cat_results, fn r -> r.participant.id == participant_id end)

        %{
          category: result.category,
          rank: if(cat_result, do: cat_result.rank),
          total: length(cat_results)
        }
      end

    race = Races.get_race!(race_id, preload: [:auto_categories])

    auto_categories =
      Enum.map(race.auto_categories, fn auto_cat ->
        auto_results =
          all_results
          |> Enum.filter(fn r -> Enum.any?(r.auto_categories, &(&1.id == auto_cat.id)) end)
          |> Ranker.rank_results()

        participant_in_cat =
          Enum.any?(auto_results, fn r -> r.participant.id == participant_id end)

        auto_result =
          Enum.find(auto_results, fn r -> r.participant.id == participant_id end)

        %{
          auto_category: auto_cat,
          rank: if(auto_result, do: auto_result.rank),
          total: length(auto_results),
          member: participant_in_cat
        }
      end)

    %{
      overall: overall,
      category: category,
      auto_categories: auto_categories
    }
  end
end
