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

    participants = Participants.list_participants_for_user(user_id)

    Enum.map(participants, fn participant ->
      race = Races.get_race!(participant.race_id)
      splits = Races.list_splits(race.id)
      all_results = get_race_results(race.id)

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

    race = Races.get_race!(race_id)
    race = Bibtime.Repo.preload(race, :auto_categories)

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
