defmodule Bibtime.Participants.CSVImport do
  @moduledoc """
  Imports participants from a CSV string.

  The CSV has columns for bib number and name (required), and optionally
  email, category and club. A header row is optional — if present it is
  used to map columns; if absent, the default positional order is:

      bib, name, email, category, club

  Recognised header tokens (case-insensitive):

    * bib         — "bib", "bib_number", "bib no", "bib #", "number", "#", "startnr", "startnummer"
    * name        — "name", "full name"  (split into first/last on whitespace)
    * first_name  — "first", "first name", "first_name", "förnamn", "fornamn"
    * last_name   — "last", "last name", "last_name", "surname", "efternamn"
    * email       — "email", "e-mail", "e-post", "epost"
    * category    — "category", "cat", "klass", "kategori"
    * club        — "club", "team", "förening", "forening"

  Category is matched by name (case-insensitive) against the race's categories.
  Duplicate bib numbers within the import OR against existing participants
  in the race cause the entire import to fail.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo
  alias Bibtime.Participants
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.RaceCategory

  @doc """
  Parses a CSV string into a list of row maps with keys
  `:bib_number, :first_name, :last_name, :email, :category, :club`.

  Returns `{:ok, rows}` or `{:error, errors}` where errors is a list of
  `%{row: integer, field: string, message: string}`.
  """
  def parse(csv_string) do
    lines =
      csv_string
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] ->
        {:error, [%{row: 0, field: "csv", message: "CSV is empty"}]}

      [first | rest] ->
        first_fields = split_csv_line(first)

        {columns, data_lines, first_row_num} =
          case detect_header(first_fields) do
            {:header, cols} -> {cols, rest, 2}
            :no_header -> {default_columns(), lines, 1}
          end

        parse_rows(data_lines, columns, first_row_num)
    end
  end

  @doc """
  Validates parsed rows against the given race.

  Checks that:
    * bib_number is present and non-empty
    * first_name is present (last_name is optional)
    * email, if present, is well-formed
    * category, if present, matches one of the race's categories
    * no duplicate bibs within the import
    * no bibs collide with existing participants in the race

  Returns `{:ok, validated_rows}` or `{:error, errors}`.

  Each validated row is a map of attrs ready for `Participants.create_participant/1`.
  """
  def validate(rows, race_id) do
    categories_by_name = load_categories_by_name(race_id)
    existing_bibs = load_existing_bibs(race_id)

    {validated, errors, _seen} =
      rows
      |> Enum.reduce({[], [], MapSet.new()}, fn row, {valid_acc, error_acc, seen} ->
        row_errors = []

        row_errors = validate_bib(row, row_errors)
        row_errors = validate_name(row, row_errors)
        row_errors = validate_email(row, row_errors)
        {category_id, row_errors} = resolve_category(row, categories_by_name, row_errors)

        row_errors =
          if MapSet.member?(existing_bibs, row.bib_number) do
            [
              %{
                row: row.row_num,
                field: "bib_number",
                message: "bib '#{row.bib_number}' already exists in the race"
              }
              | row_errors
            ]
          else
            row_errors
          end

        row_errors =
          if MapSet.member?(seen, row.bib_number) do
            [
              %{
                row: row.row_num,
                field: "bib_number",
                message: "duplicate bib '#{row.bib_number}' in the import"
              }
              | row_errors
            ]
          else
            row_errors
          end

        seen = if row.bib_number in [nil, ""], do: seen, else: MapSet.put(seen, row.bib_number)

        case row_errors do
          [] ->
            attrs = %{
              "bib_number" => row.bib_number,
              "first_name" => row.first_name,
              "last_name" => nil_if_blank(row.last_name),
              "email" => nil_if_blank(row.email),
              "club" => nil_if_blank(row.club),
              "race_id" => race_id,
              "race_category_id" => category_id
            }

            {[attrs | valid_acc], error_acc, seen}

          _ ->
            {valid_acc, error_acc ++ Enum.reverse(row_errors), seen}
        end
      end)

    case errors do
      [] -> {:ok, Enum.reverse(validated)}
      _ -> {:error, errors}
    end
  end

  @doc """
  Imports participants from a CSV string into the given race.

  Runs parse -> validate -> insert inside a transaction. All-or-nothing.

  On success, returns `{:ok, %{imported: count}}`.
  On failure, returns `{:error, errors}`.
  """
  def import(csv_string, race_id) do
    with {:ok, rows} <- parse(csv_string),
         {:ok, validated} <- validate(rows, race_id) do
      Repo.transaction(fn ->
        Enum.each(validated, fn attrs ->
          # Historic imports are a read-only record of past races, not account
          # holders: link to an existing user if the email matches one, but
          # never create accounts for people who never signed up.
          case Participants.create_participant(attrs, create_user: false) do
            {:ok, _p} -> :ok
            {:error, changeset} -> Repo.rollback({:insert_failed, changeset})
          end
        end)

        %{imported: length(validated)}
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, {:insert_failed, changeset}} -> {:error, [changeset_to_error(changeset)]}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Header detection + column mapping
  # ---------------------------------------------------------------------------

  defp default_columns do
    %{bib: 0, name: 1, email: 2, category: 3, club: 4}
  end

  defp detect_header(fields) do
    mapped =
      fields
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {raw, idx}, acc ->
        case header_token(raw) do
          nil -> acc
          key -> Map.put_new(acc, key, idx)
        end
      end)

    if map_size(mapped) > 0, do: {:header, mapped}, else: :no_header
  end

  defp header_token(raw) do
    normalised =
      raw
      |> String.downcase()
      |> String.trim()
      |> String.replace(~r/[\s_\-#]+/u, "")

    cond do
      normalised in ["bib", "bibnumber", "bibno", "number", "startnr", "startnummer"] ->
        :bib

      normalised in ["name", "fullname"] ->
        :name

      normalised in ["first", "firstname", "förnamn", "fornamn"] ->
        :first_name

      normalised in ["last", "lastname", "surname", "efternamn"] ->
        :last_name

      normalised in ["email", "emailaddress", "epost"] ->
        :email

      normalised in ["category", "cat", "klass", "kategori"] ->
        :category

      normalised in ["club", "team", "förening", "forening"] ->
        :club

      true ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Row parsing
  # ---------------------------------------------------------------------------

  defp parse_rows(lines, columns, first_row_num) do
    rows =
      lines
      |> Enum.with_index(first_row_num)
      |> Enum.map(fn {line, row_num} ->
        fields = split_csv_line(line)
        build_row(fields, columns, row_num)
      end)

    {:ok, rows}
  end

  defp build_row(fields, columns, row_num) do
    bib = get_field(fields, Map.get(columns, :bib))
    email = get_field(fields, Map.get(columns, :email))
    category = get_field(fields, Map.get(columns, :category))
    club = get_field(fields, Map.get(columns, :club))

    {first, last} =
      cond do
        Map.has_key?(columns, :first_name) or Map.has_key?(columns, :last_name) ->
          f = get_field(fields, Map.get(columns, :first_name))
          l = get_field(fields, Map.get(columns, :last_name))
          {f, l}

        true ->
          get_field(fields, Map.get(columns, :name))
          |> split_name()
      end

    %{
      row_num: row_num,
      bib_number: bib,
      first_name: first,
      last_name: last,
      email: email,
      category: category,
      club: club
    }
  end

  defp get_field(_fields, nil), do: ""

  defp get_field(fields, index) when is_integer(index) do
    fields |> Enum.at(index, "") |> String.trim()
  end

  defp split_name(nil), do: {"", ""}

  defp split_name(name) do
    parts = name |> String.trim() |> String.split(~r/\s+/, trim: true)

    case parts do
      [] -> {"", ""}
      [only] -> {only, ""}
      many -> {Enum.slice(many, 0..-2//1) |> Enum.join(" "), List.last(many)}
    end
  end

  # Minimal CSV line splitter: supports double-quoted fields with "" escapes.
  defp split_csv_line(line) do
    split_csv_line(line, :start, "", [])
  end

  defp split_csv_line("", :start, _buf, acc), do: Enum.reverse(["" | acc])
  defp split_csv_line("", :unquoted, buf, acc), do: Enum.reverse([buf | acc])
  defp split_csv_line("", :quoted, buf, acc), do: Enum.reverse([buf | acc])
  defp split_csv_line("", :after_quote, buf, acc), do: Enum.reverse([buf | acc])

  defp split_csv_line(<<"\"", rest::binary>>, :start, _buf, acc),
    do: split_csv_line(rest, :quoted, "", acc)

  defp split_csv_line(<<",", rest::binary>>, :start, _buf, acc),
    do: split_csv_line(rest, :start, "", ["" | acc])

  defp split_csv_line(<<c::utf8, rest::binary>>, :start, _buf, acc),
    do: split_csv_line(rest, :unquoted, <<c::utf8>>, acc)

  defp split_csv_line(<<",", rest::binary>>, :unquoted, buf, acc),
    do: split_csv_line(rest, :start, "", [buf | acc])

  defp split_csv_line(<<c::utf8, rest::binary>>, :unquoted, buf, acc),
    do: split_csv_line(rest, :unquoted, buf <> <<c::utf8>>, acc)

  defp split_csv_line(<<"\"\"", rest::binary>>, :quoted, buf, acc),
    do: split_csv_line(rest, :quoted, buf <> "\"", acc)

  defp split_csv_line(<<"\"", rest::binary>>, :quoted, buf, acc),
    do: split_csv_line(rest, :after_quote, buf, acc)

  defp split_csv_line(<<c::utf8, rest::binary>>, :quoted, buf, acc),
    do: split_csv_line(rest, :quoted, buf <> <<c::utf8>>, acc)

  defp split_csv_line(<<",", rest::binary>>, :after_quote, buf, acc),
    do: split_csv_line(rest, :start, "", [buf | acc])

  defp split_csv_line(<<_::utf8, rest::binary>>, :after_quote, buf, acc),
    do: split_csv_line(rest, :after_quote, buf, acc)

  # ---------------------------------------------------------------------------
  # Validation helpers
  # ---------------------------------------------------------------------------

  defp validate_bib(%{bib_number: bib, row_num: n}, errors) do
    cond do
      bib in [nil, ""] ->
        [%{row: n, field: "bib_number", message: "bib number is required"} | errors]

      true ->
        errors
    end
  end

  defp validate_name(%{first_name: f, row_num: n}, errors) do
    if f in [nil, ""] do
      [%{row: n, field: "name", message: "name is required"} | errors]
    else
      errors
    end
  end

  defp validate_email(%{email: email, row_num: n}, errors) do
    cond do
      email in [nil, ""] ->
        errors

      Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email) ->
        errors

      true ->
        [%{row: n, field: "email", message: "invalid email '#{email}'"} | errors]
    end
  end

  defp resolve_category(%{category: cat, row_num: n}, by_name, errors) do
    cond do
      cat in [nil, ""] ->
        {nil, errors}

      true ->
        case Map.get(by_name, String.downcase(cat)) do
          nil ->
            {nil,
             [
               %{
                 row: n,
                 field: "category",
                 message: "category '#{cat}' not found in race"
               }
               | errors
             ]}

          category ->
            {category.id, errors}
        end
    end
  end

  defp load_categories_by_name(race_id) do
    RaceCategory
    |> where([c], c.race_id == ^race_id)
    |> Repo.all()
    |> Map.new(fn c -> {String.downcase(c.name), c} end)
  end

  defp load_existing_bibs(race_id) do
    Participant
    |> where([p], p.race_id == ^race_id)
    |> select([p], p.bib_number)
    |> Repo.all()
    |> MapSet.new()
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(s), do: s

  defp changeset_to_error(changeset) do
    messages =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    %{row: 0, field: "insert", message: "failed to insert: #{inspect(messages)}"}
  end
end
