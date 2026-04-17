defmodule Bibtime.Participants.CSVImportTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Participants.CSVImport
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.{Race, RaceCategory}

  defp create_race! do
    Repo.insert!(%Race{
      name: "Import Race",
      slug: "import-race-#{System.unique_integer([:positive])}",
      race_type: :running,
      status: :draft
    })
  end

  defp create_category!(race, name) do
    Repo.insert!(%RaceCategory{name: name, race_id: race.id})
  end

  defp create_participant!(race, bib) do
    Repo.insert!(%Participant{
      bib_number: bib,
      first_name: "Existing",
      last_name: "Runner",
      race_id: race.id
    })
  end

  describe "parse/1" do
    test "parses CSV with no header using default column order" do
      csv = """
      101,Alice Runner,alice@example.com,Elite,Stockholm AC
      102,Bob Cyclist,,Sport,
      103,Carol Swimmer Long,carol@example.com,,
      """

      assert {:ok, rows} = CSVImport.parse(csv)
      assert length(rows) == 3

      [r1, r2, r3] = rows
      assert r1.bib_number == "101"
      assert r1.first_name == "Alice"
      assert r1.last_name == "Runner"
      assert r1.email == "alice@example.com"
      assert r1.category == "Elite"
      assert r1.club == "Stockholm AC"

      assert r2.email == ""
      assert r2.club == ""
      assert r3.first_name == "Carol Swimmer"
      assert r3.last_name == "Long"
    end

    test "parses CSV with a header row" do
      csv = """
      Bib,Name,Email,Category,Club
      5,Alice Runner,alice@example.com,Elite,Stockholm AC
      """

      assert {:ok, [row]} = CSVImport.parse(csv)
      assert row.bib_number == "5"
      assert row.first_name == "Alice"
      assert row.last_name == "Runner"
      assert row.email == "alice@example.com"
      assert row.row_num == 2
    end

    test "header order can be shuffled and is honoured" do
      csv = """
      name,bib,club
      Alice Runner,42,Stockholm AC
      """

      assert {:ok, [row]} = CSVImport.parse(csv)
      assert row.bib_number == "42"
      assert row.first_name == "Alice"
      assert row.last_name == "Runner"
      assert row.club == "Stockholm AC"
      assert row.email == ""
    end

    test "supports separate first_name / last_name header columns" do
      csv = """
      bib,first_name,last_name,email
      7,Alice,Runner,alice@example.com
      """

      assert {:ok, [row]} = CSVImport.parse(csv)
      assert row.first_name == "Alice"
      assert row.last_name == "Runner"
    end

    test "handles quoted values containing commas" do
      csv = ~s|101,"Alice Runner",alice@example.com,Elite,"Club, Inc."|
      assert {:ok, [row]} = CSVImport.parse(csv)
      assert row.first_name == "Alice"
      assert row.last_name == "Runner"
      assert row.club == "Club, Inc."
    end

    test "returns error for empty CSV" do
      assert {:error, [%{field: "csv", message: "CSV is empty"}]} = CSVImport.parse("")
    end
  end

  describe "validate/2" do
    test "succeeds with valid rows" do
      race = create_race!()
      elite = create_category!(race, "Elite")

      csv = """
      bib,name,email,category,club
      101,Alice Runner,alice@example.com,Elite,Stockholm AC
      102,Bob Cyclist,bob@example.com,,
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:ok, [a1, a2]} = CSVImport.validate(rows, race.id)
      assert a1["bib_number"] == "101"
      assert a1["first_name"] == "Alice"
      assert a1["last_name"] == "Runner"
      assert a1["race_category_id"] == elite.id
      assert a1["club"] == "Stockholm AC"
      assert a2["race_category_id"] == nil
      assert a2["club"] == nil
    end

    test "rejects duplicate bibs inside the import" do
      race = create_race!()

      csv = """
      101,Alice Runner
      101,Bob Cyclist
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, errors} = CSVImport.validate(rows, race.id)
      assert Enum.any?(errors, &String.contains?(&1.message, "duplicate bib '101'"))
    end

    test "rejects bibs that already exist in the race" do
      race = create_race!()
      create_participant!(race, "101")

      csv = """
      101,Alice Runner
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, [err]} = CSVImport.validate(rows, race.id)
      assert err.field == "bib_number"
      assert String.contains?(err.message, "already exists")
    end

    test "rejects missing bib numbers" do
      race = create_race!()

      csv = """
      ,Alice Runner
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, [err]} = CSVImport.validate(rows, race.id)
      assert err.field == "bib_number"
    end

    test "rejects single-word names" do
      race = create_race!()

      csv = """
      101,Alice
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, [err]} = CSVImport.validate(rows, race.id)
      assert err.field == "name"
    end

    test "rejects unknown category names" do
      race = create_race!()

      csv = """
      101,Alice Runner,,Ghost,
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, [err]} = CSVImport.validate(rows, race.id)
      assert err.field == "category"
    end

    test "matches categories case-insensitively" do
      race = create_race!()
      elite = create_category!(race, "Elite")

      csv = """
      101,Alice Runner,,ELITE,
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:ok, [attrs]} = CSVImport.validate(rows, race.id)
      assert attrs["race_category_id"] == elite.id
    end

    test "rejects malformed email" do
      race = create_race!()

      csv = """
      101,Alice Runner,not-an-email,,
      """

      {:ok, rows} = CSVImport.parse(csv)
      assert {:error, [err]} = CSVImport.validate(rows, race.id)
      assert err.field == "email"
    end
  end

  describe "import/2" do
    test "inserts all rows on success" do
      race = create_race!()
      create_category!(race, "Elite")

      csv = """
      bib,name,email,category,club
      101,Alice Runner,alice@example.com,Elite,Stockholm AC
      102,Bob Cyclist,,,
      """

      assert {:ok, %{imported: 2}} = CSVImport.import(csv, race.id)

      assert Repo.aggregate(
               from(p in Participant, where: p.race_id == ^race.id),
               :count
             ) == 2
    end

    test "is all-or-nothing on validation error" do
      race = create_race!()
      create_participant!(race, "101")

      csv = """
      102,Bob Cyclist
      101,Alice Runner
      """

      assert {:error, _errors} = CSVImport.import(csv, race.id)
      # Only the pre-existing participant remains; the valid 102 row is rolled back.
      assert Repo.aggregate(
               from(p in Participant, where: p.race_id == ^race.id),
               :count
             ) == 1
    end
  end
end
