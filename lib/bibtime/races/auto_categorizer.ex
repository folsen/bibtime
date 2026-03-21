defmodule Bibtime.Races.AutoCategorizer do
  @moduledoc """
  Pure functions for matching participants to automatic categories.

  Auto categories are computed at results display time from participant
  fields (gender, birth_date) — they are never stored on the participant.
  """

  @doc """
  Returns the list of auto categories that match the given participant.

  A participant can match multiple auto categories (e.g., one gender
  category and one age group category).
  """
  def match(participant, auto_categories, race_date) do
    Enum.filter(auto_categories, fn cat ->
      matches?(participant, cat, race_date)
    end)
  end

  defp matches?(participant, %{type: :gender} = cat, _race_date) do
    participant.gender == cat.gender_value
  end

  defp matches?(participant, %{type: :age_group} = cat, race_date) do
    case compute_age(participant.birth_date, race_date) do
      nil -> false
      age -> in_age_range?(age, cat.min_age, cat.max_age)
    end
  end

  @doc """
  Computes age in years as of the given reference date.

  Returns nil if birth_date is nil.
  """
  def compute_age(nil, _reference_date), do: nil

  def compute_age(birth_date, reference_date) do
    age = reference_date.year - birth_date.year

    if Date.compare(
         %{reference_date | year: reference_date.year},
         %{birth_date | year: reference_date.year}
       ) == :lt do
      age - 1
    else
      age
    end
  end

  defp in_age_range?(_age, nil, nil), do: true
  defp in_age_range?(age, min, nil), do: age >= min
  defp in_age_range?(age, nil, max), do: age < max
  defp in_age_range?(age, min, max), do: age >= min and age < max
end
