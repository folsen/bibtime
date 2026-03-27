defmodule Bibtime.RacesFixtures do
  @moduledoc """
  Test helpers for creating race-related entities.
  """

  alias Bibtime.Races

  def unique_slug, do: "race-#{System.unique_integer([:positive])}"

  def valid_race_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test Race",
      slug: unique_slug(),
      race_type: :running,
      status: :draft,
      date: ~D[2026-06-01],
      location: "Test City"
    })
  end

  def race_fixture(attrs \\ %{}) do
    {:ok, race} =
      attrs
      |> valid_race_attributes()
      |> Races.create_race()

    race
  end

  def category_fixture(race, attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{name: "Open", race_id: race.id})
      |> Races.create_category()

    category
  end

  def split_fixture(race, attrs \\ %{}) do
    {:ok, split} =
      attrs
      |> Enum.into(%{
        name: "Split #{System.unique_integer([:positive])}",
        short_name: "s#{System.unique_integer([:positive])}",
        leg_type: :run,
        race_id: race.id,
        sort_order: 0
      })
      |> Races.create_split()

    split
  end

  @doc """
  Creates a triathlon race with swim/bike/run splits, ready for timing.
  Returns {race, [swim_split, bike_split, run_split]}.
  """
  def triathlon_fixture(race_attrs \\ %{}) do
    race =
      race_fixture(Map.merge(%{race_type: :triathlon, status: :in_progress}, race_attrs))

    swim =
      split_fixture(race, %{
        name: "Swim",
        short_name: "swim",
        leg_type: :swim,
        sort_order: 1
      })

    bike =
      split_fixture(race, %{
        name: "Bike",
        short_name: "bike",
        leg_type: :bike,
        sort_order: 2
      })

    run =
      split_fixture(race, %{
        name: "Run",
        short_name: "run",
        leg_type: :run,
        sort_order: 3
      })

    {race, [swim, bike, run]}
  end
end
