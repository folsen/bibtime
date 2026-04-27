defmodule Bibtime.Races do
  @moduledoc """
  The Races context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Accounts.User
  alias Bibtime.Races.Race
  alias Bibtime.Races.RaceCategory
  alias Bibtime.Races.RaceAutoCategory
  alias Bibtime.Races.Split
  alias Bibtime.Races.Templates

  ## Races

  def list_races do
    Race
    |> order_by(desc: :date)
    |> Repo.all()
  end

  @doc """
  Returns the races the given scope is allowed to see. Admins see everything;
  everyone else only sees races whose status has progressed past `:draft`.
  """
  def list_visible_races(scope) do
    if scope_admin?(scope) do
      list_races()
    else
      Race
      |> where([r], r.status != :draft)
      |> order_by(desc: :date)
      |> Repo.all()
    end
  end

  def get_race(id), do: Repo.get(Race, id)

  def get_race!(id, opts \\ []) do
    race = Repo.get!(Race, id)

    case Keyword.get(opts, :preload) do
      nil ->
        race

      preloads ->
        preloads =
          Enum.map(preloads, fn
            :splits -> {:splits, order_by(Split, :sort_order)}
            other -> other
          end)

        Repo.preload(race, preloads)
    end
  end

  def get_race_by_slug!(slug) do
    Repo.get_by!(Race, slug: slug)
  end

  @doc """
  Like `get_race_by_slug!/1` but raises `Ecto.NoResultsError` (→ 404) if the
  race is in `:draft` status and the scope is not an admin.
  """
  def get_visible_race_by_slug!(slug, scope) do
    race = Repo.get_by!(Race, slug: slug)

    if race.status == :draft and not scope_admin?(scope) do
      raise Ecto.NoResultsError, queryable: Race
    end

    race
  end

  defp scope_admin?(%{user: %User{} = user}), do: User.admin?(user)
  defp scope_admin?(_), do: false

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

  def create_race_from_template(race_attrs, template_id) do
    template = Templates.get(template_id)

    if template do
      Repo.transaction(fn ->
        race_attrs = Map.put_new(race_attrs, "race_type", Atom.to_string(template.race_type))

        case create_race(race_attrs) do
          {:ok, race} ->
            copy_race_children(race, template)
            get_race!(race.id, preload: [:categories, :auto_categories, :splits])

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)
    else
      create_race(race_attrs)
    end
  end

  def clone_race(source_race_id, race_attrs) do
    source = get_race!(source_race_id, preload: [:categories, :auto_categories, :splits])

    Repo.transaction(fn ->
      race_attrs = Map.put_new(race_attrs, "race_type", Atom.to_string(source.race_type))

      case create_race(race_attrs) do
        {:ok, race} ->
          copy_race_children(race, source)
          get_race!(race.id, preload: [:categories, :auto_categories, :splits])

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp copy_race_children(race, source) do
    for cat <- Map.get(source, :categories, []) do
      create_category(%{
        "race_id" => race.id,
        "name" => cat.name,
        "distance_label" => cat.distance_label,
        "gender" => Atom.to_string(cat.gender),
        "min_age" => Map.get(cat, :min_age),
        "max_age" => Map.get(cat, :max_age),
        "sort_order" => cat.sort_order
      })
    end

    for split <- source.splits do
      create_split(%{
        "race_id" => race.id,
        "name" => split.name,
        "short_name" => split.short_name,
        "leg_type" => Atom.to_string(split.leg_type),
        "distance_meters" => split.distance_meters,
        "sort_order" => split.sort_order
      })
    end

    for auto_cat <- Map.get(source, :auto_categories, []) do
      create_auto_category(%{
        "race_id" => race.id,
        "type" => Atom.to_string(auto_cat.type),
        "name" => auto_cat.name,
        "gender_value" =>
          if(Map.get(auto_cat, :gender_value), do: Atom.to_string(auto_cat.gender_value)),
        "min_age" => Map.get(auto_cat, :min_age),
        "max_age" => Map.get(auto_cat, :max_age),
        "sort_order" => auto_cat.sort_order
      })
    end
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

  ## Auto Categories

  def list_auto_categories(race_id) do
    RaceAutoCategory
    |> where([c], c.race_id == ^race_id)
    |> order_by(:sort_order)
    |> Repo.all()
  end

  def get_auto_category!(id) do
    Repo.get!(RaceAutoCategory, id)
  end

  def create_auto_category(attrs \\ %{}) do
    %RaceAutoCategory{}
    |> RaceAutoCategory.changeset(attrs)
    |> Repo.insert()
  end

  def delete_auto_category(%RaceAutoCategory{} = auto_category) do
    Repo.delete(auto_category)
  end

  def change_auto_category(%RaceAutoCategory{} = auto_category, attrs \\ %{}) do
    RaceAutoCategory.changeset(auto_category, attrs)
  end

  def add_gender_auto_categories(race_id) do
    [
      %{
        "race_id" => race_id,
        "type" => "gender",
        "name" => "Men",
        "gender_value" => "male",
        "sort_order" => 1
      },
      %{
        "race_id" => race_id,
        "type" => "gender",
        "name" => "Women",
        "gender_value" => "female",
        "sort_order" => 2
      }
    ]
    |> Enum.each(&create_auto_category/1)
  end

  def add_age_group_auto_categories(race_id) do
    [
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "0-19",
        "min_age" => 0,
        "max_age" => 20,
        "sort_order" => 10
      },
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "20-29",
        "min_age" => 20,
        "max_age" => 30,
        "sort_order" => 11
      },
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "30-39",
        "min_age" => 30,
        "max_age" => 40,
        "sort_order" => 12
      },
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "40-49",
        "min_age" => 40,
        "max_age" => 50,
        "sort_order" => 13
      },
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "50-59",
        "min_age" => 50,
        "max_age" => 60,
        "sort_order" => 14
      },
      %{
        "race_id" => race_id,
        "type" => "age_group",
        "name" => "60+",
        "min_age" => 60,
        "max_age" => nil,
        "sort_order" => 15
      }
    ]
    |> Enum.each(&create_auto_category/1)
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
