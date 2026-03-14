defmodule Bibtime.Races do
  @moduledoc """
  The Races context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Races.Race
  alias Bibtime.Races.RaceCategory
  alias Bibtime.Races.Split

  ## Races

  def list_races do
    Race
    |> order_by(desc: :date)
    |> Repo.all()
  end

  def get_race!(id) do
    Race
    |> Repo.get!(id)
    |> Repo.preload([:categories, :splits])
  end

  def get_race_by_slug!(slug) do
    Repo.get_by!(Race, slug: slug)
  end

  def create_race(attrs \\ %{}) do
    %Race{}
    |> Race.changeset(attrs)
    |> Repo.insert()
  end

  def update_race(%Race{} = race, attrs) do
    race
    |> Race.changeset(attrs)
    |> Repo.update()
  end

  def delete_race(%Race{} = race) do
    Repo.delete(race)
  end

  def change_race(%Race{} = race, attrs \\ %{}) do
    Race.changeset(race, attrs)
  end

  ## Categories

  def list_categories(race_id) do
    RaceCategory
    |> where([c], c.race_id == ^race_id)
    |> order_by(:sort_order)
    |> Repo.all()
  end

  def get_category!(id) do
    Repo.get!(RaceCategory, id)
  end

  def create_category(attrs \\ %{}) do
    %RaceCategory{}
    |> RaceCategory.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%RaceCategory{} = category, attrs) do
    category
    |> RaceCategory.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%RaceCategory{} = category) do
    Repo.delete(category)
  end

  def change_category(%RaceCategory{} = category, attrs \\ %{}) do
    RaceCategory.changeset(category, attrs)
  end

  ## Splits

  def list_splits(race_id) do
    Split
    |> where([s], s.race_id == ^race_id)
    |> order_by(:sort_order)
    |> Repo.all()
  end

  def get_split!(id) do
    Repo.get!(Split, id)
  end

  def create_split(attrs \\ %{}) do
    %Split{}
    |> Split.changeset(attrs)
    |> Repo.insert()
  end

  def update_split(%Split{} = split, attrs) do
    split
    |> Split.changeset(attrs)
    |> Repo.update()
  end

  def delete_split(%Split{} = split) do
    Repo.delete(split)
  end

  def change_split(%Split{} = split, attrs \\ %{}) do
    Split.changeset(split, attrs)
  end
end
