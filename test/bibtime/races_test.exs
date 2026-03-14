defmodule Bibtime.RacesTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Races
  alias Bibtime.Races.{Race, RaceCategory, Split}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_race_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Test Race",
        slug: "test-race-#{System.unique_integer([:positive])}",
        race_type: :running,
        status: :draft,
        date: ~D[2026-06-01],
        location: "Somewhere"
      },
      overrides
    )
  end

  defp create_race!(overrides \\ %{}) do
    {:ok, race} = Races.create_race(valid_race_attrs(overrides))
    race
  end

  # ---------------------------------------------------------------------------
  # Races
  # ---------------------------------------------------------------------------

  describe "create_race/1" do
    test "with valid attrs succeeds" do
      attrs = valid_race_attrs()
      assert {:ok, %Race{} = race} = Races.create_race(attrs)
      assert race.name == attrs.name
      assert race.slug == attrs.slug
      assert race.race_type == :running
      assert race.status == :draft
    end

    test "with missing name fails" do
      attrs = valid_race_attrs(%{name: nil})
      assert {:error, changeset} = Races.create_race(attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "with duplicate slug fails" do
      race = create_race!(%{slug: "dup-slug"})
      attrs = valid_race_attrs(%{slug: race.slug})
      assert {:error, changeset} = Races.create_race(attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "get_race!/1" do
    test "returns race with preloaded categories and splits" do
      race = create_race!()

      Repo.insert!(%RaceCategory{name: "Elite", race_id: race.id})
      Repo.insert!(%Split{name: "Swim", short_name: "swim", leg_type: :swim, race_id: race.id})

      fetched = Races.get_race!(race.id)
      assert fetched.id == race.id
      assert length(fetched.categories) == 1
      assert hd(fetched.categories).name == "Elite"
      assert length(fetched.splits) == 1
      assert hd(fetched.splits).name == "Swim"
    end
  end

  describe "get_race_by_slug!/1" do
    test "returns race by slug" do
      race = create_race!(%{slug: "my-unique-slug"})
      fetched = Races.get_race_by_slug!("my-unique-slug")
      assert fetched.id == race.id
    end

    test "raises when slug not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Races.get_race_by_slug!("nonexistent-slug")
      end
    end
  end

  describe "update_race/2" do
    test "updates race attributes" do
      race = create_race!()
      assert {:ok, updated} = Races.update_race(race, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end
  end

  describe "delete_race/1" do
    test "deletes the race" do
      race = create_race!()
      assert {:ok, %Race{}} = Races.delete_race(race)

      assert_raise Ecto.NoResultsError, fn ->
        Races.get_race!(race.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Categories
  # ---------------------------------------------------------------------------

  describe "categories" do
    test "create_category/1 with valid attrs succeeds" do
      race = create_race!()

      assert {:ok, %RaceCategory{} = cat} =
               Races.create_category(%{name: "Senior Men", race_id: race.id})

      assert cat.name == "Senior Men"
      assert cat.race_id == race.id
    end

    test "create_category/1 with missing name fails" do
      race = create_race!()
      assert {:error, changeset} = Races.create_category(%{race_id: race.id})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "list_categories/1 returns categories scoped to race, ordered by sort_order" do
      race1 = create_race!()
      race2 = create_race!()

      Races.create_category(%{name: "Cat B", race_id: race1.id, sort_order: 2})
      Races.create_category(%{name: "Cat A", race_id: race1.id, sort_order: 1})
      Races.create_category(%{name: "Other Race Cat", race_id: race2.id, sort_order: 1})

      cats = Races.list_categories(race1.id)
      assert length(cats) == 2
      assert Enum.map(cats, & &1.name) == ["Cat A", "Cat B"]
    end

    test "delete_category/1 removes the category" do
      race = create_race!()
      {:ok, cat} = Races.create_category(%{name: "To Delete", race_id: race.id})
      assert {:ok, %RaceCategory{}} = Races.delete_category(cat)
      assert Races.list_categories(race.id) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Splits
  # ---------------------------------------------------------------------------

  describe "splits" do
    test "create_split/1 with valid attrs succeeds" do
      race = create_race!()

      assert {:ok, %Split{} = split} =
               Races.create_split(%{
                 name: "Swim Leg",
                 short_name: "swim",
                 leg_type: :swim,
                 race_id: race.id
               })

      assert split.name == "Swim Leg"
      assert split.short_name == "swim"
      assert split.leg_type == :swim
    end

    test "create_split/1 with missing fields fails" do
      race = create_race!()
      assert {:error, changeset} = Races.create_split(%{race_id: race.id})
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:short_name]
      assert errors[:leg_type]
    end

    test "list_splits/1 returns splits scoped to race, ordered by sort_order" do
      race1 = create_race!()
      race2 = create_race!()

      Races.create_split(%{name: "Run", short_name: "run", leg_type: :run, race_id: race1.id, sort_order: 2})
      Races.create_split(%{name: "Swim", short_name: "swim", leg_type: :swim, race_id: race1.id, sort_order: 1})
      Races.create_split(%{name: "Other", short_name: "other", leg_type: :other, race_id: race2.id, sort_order: 1})

      splits = Races.list_splits(race1.id)
      assert length(splits) == 2
      assert Enum.map(splits, & &1.short_name) == ["swim", "run"]
    end

    test "delete_split/1 removes the split" do
      race = create_race!()
      {:ok, split} = Races.create_split(%{name: "Temp", short_name: "tmp", leg_type: :other, race_id: race.id})
      assert {:ok, %Split{}} = Races.delete_split(split)
      assert Races.list_splits(race.id) == []
    end
  end
end
