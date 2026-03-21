defmodule Bibtime.Races.AutoCategorizerTest do
  use ExUnit.Case, async: true

  alias Bibtime.Races.AutoCategorizer

  defp make_participant(attrs) do
    Map.merge(
      %{gender: nil, birth_date: nil},
      attrs
    )
  end

  defp make_auto_cat(attrs) do
    Map.merge(
      %{id: 1, type: :gender, name: "Test", gender_value: nil, min_age: nil, max_age: nil},
      attrs
    )
  end

  describe "match/3 with gender categories" do
    test "matches male participant to male gender category" do
      participant = make_participant(%{gender: :male})
      cats = [make_auto_cat(%{id: 1, type: :gender, name: "Men", gender_value: :male})]

      assert [%{id: 1}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "does not match female participant to male gender category" do
      participant = make_participant(%{gender: :female})
      cats = [make_auto_cat(%{id: 1, type: :gender, name: "Men", gender_value: :male})]

      assert [] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "matches participant to multiple gender categories" do
      participant = make_participant(%{gender: :female})

      cats = [
        make_auto_cat(%{id: 1, type: :gender, name: "Men", gender_value: :male}),
        make_auto_cat(%{id: 2, type: :gender, name: "Women", gender_value: :female})
      ]

      assert [%{id: 2}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "does not match when participant has no gender" do
      participant = make_participant(%{gender: nil})
      cats = [make_auto_cat(%{id: 1, type: :gender, name: "Men", gender_value: :male})]

      assert [] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end
  end

  describe "match/3 with age group categories" do
    test "matches participant to correct age group" do
      # Born 1996-01-01, race on 2026-06-15 -> age 30
      participant = make_participant(%{birth_date: ~D[1996-01-01]})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "20-29", min_age: 20, max_age: 30}),
        make_auto_cat(%{id: 2, type: :age_group, name: "30-39", min_age: 30, max_age: 40})
      ]

      assert [%{id: 2}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "age boundary: max_age is exclusive" do
      # Born 1997-01-01, race on 2026-06-15 -> age 29
      participant = make_participant(%{birth_date: ~D[1997-01-01]})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "20-29", min_age: 20, max_age: 30})
      ]

      assert [%{id: 1}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "handles open-ended max age (60+)" do
      # Born 1960-01-01, race on 2026-06-15 -> age 66
      participant = make_participant(%{birth_date: ~D[1960-01-01]})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "60+", min_age: 60, max_age: nil})
      ]

      assert [%{id: 1}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "does not match when birth_date is nil" do
      participant = make_participant(%{birth_date: nil})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "20-29", min_age: 20, max_age: 30})
      ]

      assert [] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "correctly handles birthday not yet passed in race year" do
      # Born 1996-12-25, race on 2026-06-15 -> age 29 (birthday hasn't happened yet)
      participant = make_participant(%{birth_date: ~D[1996-12-25]})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "20-29", min_age: 20, max_age: 30}),
        make_auto_cat(%{id: 2, type: :age_group, name: "30-39", min_age: 30, max_age: 40})
      ]

      assert [%{id: 1}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end

    test "correctly handles birthday already passed in race year" do
      # Born 1996-03-01, race on 2026-06-15 -> age 30
      participant = make_participant(%{birth_date: ~D[1996-03-01]})

      cats = [
        make_auto_cat(%{id: 1, type: :age_group, name: "20-29", min_age: 20, max_age: 30}),
        make_auto_cat(%{id: 2, type: :age_group, name: "30-39", min_age: 30, max_age: 40})
      ]

      assert [%{id: 2}] = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
    end
  end

  describe "match/3 with mixed categories" do
    test "participant matches both gender and age group" do
      participant = make_participant(%{gender: :male, birth_date: ~D[1996-01-01]})

      cats = [
        make_auto_cat(%{id: 1, type: :gender, name: "Men", gender_value: :male}),
        make_auto_cat(%{id: 2, type: :gender, name: "Women", gender_value: :female}),
        make_auto_cat(%{id: 3, type: :age_group, name: "30-39", min_age: 30, max_age: 40})
      ]

      result = AutoCategorizer.match(participant, cats, ~D[2026-06-15])
      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == 1))
      assert Enum.any?(result, &(&1.id == 3))
    end
  end

  describe "compute_age/2" do
    test "basic age calculation" do
      assert AutoCategorizer.compute_age(~D[2000-01-01], ~D[2026-06-15]) == 26
    end

    test "birthday not yet passed" do
      assert AutoCategorizer.compute_age(~D[2000-12-25], ~D[2026-06-15]) == 25
    end

    test "birthday on race day" do
      assert AutoCategorizer.compute_age(~D[2000-06-15], ~D[2026-06-15]) == 26
    end

    test "returns nil for nil birth_date" do
      assert AutoCategorizer.compute_age(nil, ~D[2026-06-15]) == nil
    end
  end
end
