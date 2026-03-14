defmodule Bibtime.Timing.CSVImport do
  @moduledoc """
  Imports split times from CSV data.

  Expected CSV format:
  bib_number,split_short_name,elapsed_time

  Where elapsed_time can be:
  - HH:MM:SS.mmm (e.g., "00:15:30.500")
  - HH:MM:SS (e.g., "00:15:30")
  - MM:SS (e.g., "15:30")
  - Integer milliseconds (e.g., "930500")
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.Split
  alias Bibtime.Timing

  @doc """
  Parses a CSV string into a list of row maps.

  Returns `{:ok, rows}` where each row is
  `%{bib_number: string, split_short_name: string, elapsed_time: string}`,
  or `{:error, errors}` with a list of parse error maps.
  """
  def parse(csv_string) do
    lines =
      csv_string
      |> String.trim()
      |> String.split(~r/\r?\n/)
      |> Enum.reject(&(String.trim(&1) == ""))

    case lines do
      [] ->
        {:error, [%{row: 0, field: "csv", message: "CSV is empty"}]}

      [_header | data_lines] ->
        {rows, errors} =
          data_lines
          |> Enum.with_index(2)
          |> Enum.reduce({[], []}, fn {line, row_num}, {rows_acc, errors_acc} ->
            fields = String.split(line, ",")

            case fields do
              [bib_number, split_short_name, elapsed_time | _rest] ->
                row = %{
                  bib_number: String.trim(bib_number),
                  split_short_name: String.trim(split_short_name),
                  elapsed_time: String.trim(elapsed_time)
                }

                {[row | rows_acc], errors_acc}

              _ ->
                error = %{
                  row: row_num,
                  field: "csv",
                  message: "expected at least 3 columns (bib_number, split_short_name, elapsed_time)"
                }

                {rows_acc, [error | errors_acc]}
            end
          end)

        case errors do
          [] -> {:ok, Enum.reverse(rows)}
          _ -> {:error, Enum.reverse(errors)}
        end
    end
  end

  @doc """
  Validates parsed rows against the given race.

  Checks that:
  - Each `bib_number` exists as a participant in the race
  - Each `split_short_name` matches a split in the race
  - Each `elapsed_time` is parseable
  - There are no duplicate bib+split combinations in the import

  Returns `{:ok, validated_rows}` or `{:error, errors}` where errors is a list of
  `%{row: integer, field: string, message: string}`.

  Each validated row includes resolved `:participant_id`, `:split_id`, and `:elapsed_ms`.
  """
  def validate(rows, race_id) do
    participants_by_bib = load_participants_by_bib(race_id)
    splits_by_short_name = load_splits_by_short_name(race_id)

    {validated, errors, _seen} =
      rows
      |> Enum.with_index(2)
      |> Enum.reduce({[], [], MapSet.new()}, fn {row, row_num}, {valid_acc, error_acc, seen} ->
        row_errors = []

        # Validate bib_number
        {participant_id, row_errors} =
          case Map.get(participants_by_bib, row.bib_number) do
            nil ->
              {nil, [%{row: row_num, field: "bib_number", message: "participant with bib '#{row.bib_number}' not found in race"} | row_errors]}

            participant ->
              {participant.id, row_errors}
          end

        # Validate split_short_name
        {split_id, row_errors} =
          case Map.get(splits_by_short_name, row.split_short_name) do
            nil ->
              {nil, [%{row: row_num, field: "split_short_name", message: "split '#{row.split_short_name}' not found in race"} | row_errors]}

            split ->
              {split.id, row_errors}
          end

        # Validate elapsed_time
        {elapsed_ms, row_errors} =
          case parse_time(row.elapsed_time) do
            {:ok, ms} ->
              {ms, row_errors}

            :error ->
              {nil, [%{row: row_num, field: "elapsed_time", message: "invalid time format '#{row.elapsed_time}'"} | row_errors]}
          end

        # Check for duplicates within the import
        dup_key = {row.bib_number, row.split_short_name}

        row_errors =
          if MapSet.member?(seen, dup_key) do
            [%{row: row_num, field: "bib_number,split_short_name", message: "duplicate entry for bib '#{row.bib_number}' at split '#{row.split_short_name}'"} | row_errors]
          else
            row_errors
          end

        seen = MapSet.put(seen, dup_key)

        case row_errors do
          [] ->
            validated_row = %{
              participant_id: participant_id,
              split_id: split_id,
              elapsed_ms: elapsed_ms,
              source: :import
            }

            {[validated_row | valid_acc], error_acc, seen}

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
  Parses a time string into milliseconds.

  Supported formats:
  - `"HH:MM:SS.mmm"` (e.g., `"00:15:30.500"`)
  - `"HH:MM:SS"` (e.g., `"00:15:30"`)
  - `"MM:SS"` (e.g., `"15:30"`)
  - Plain integer milliseconds (e.g., `"930500"`)

  Returns `{:ok, milliseconds}` or `:error`.
  """
  def parse_time(time_string) do
    time_string = String.trim(time_string)

    cond do
      # HH:MM:SS.mmm
      Regex.match?(~r/^\d+:\d{2}:\d{2}\.\d+$/, time_string) ->
        parse_hms_ms(time_string)

      # HH:MM:SS
      Regex.match?(~r/^\d+:\d{2}:\d{2}$/, time_string) ->
        parse_hms(time_string)

      # MM:SS
      Regex.match?(~r/^\d+:\d{2}$/, time_string) ->
        parse_ms(time_string)

      # Plain integer milliseconds
      Regex.match?(~r/^\d+$/, time_string) ->
        case Integer.parse(time_string) do
          {ms, ""} -> {:ok, ms}
          _ -> :error
        end

      true ->
        :error
    end
  end

  @doc """
  Imports split times from a CSV string for the given race.

  Orchestrates parse -> validate -> insert. All inserts are wrapped in a
  database transaction so it is all-or-nothing.

  On success, returns `{:ok, %{imported: count}}`.
  On failure, returns `{:error, errors}`.
  """
  def import(csv_string, race_id) do
    with {:ok, rows} <- parse(csv_string),
         {:ok, validated_rows} <- validate(rows, race_id) do
      Repo.transaction(fn ->
        Enum.each(validated_rows, fn row ->
          case Timing.record_split_time(row) do
            {:ok, _split_time} ->
              :ok

            {:error, changeset} ->
              Repo.rollback({:insert_failed, changeset})
          end
        end)

        %{imported: length(validated_rows)}
      end)
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, {:insert_failed, changeset}} -> {:error, [changeset_to_error(changeset)]}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_participants_by_bib(race_id) do
    Participant
    |> where([p], p.race_id == ^race_id)
    |> Repo.all()
    |> Map.new(&{&1.bib_number, &1})
  end

  defp load_splits_by_short_name(race_id) do
    Split
    |> where([s], s.race_id == ^race_id)
    |> Repo.all()
    |> Map.new(&{&1.short_name, &1})
  end

  defp parse_hms_ms(time_string) do
    [hms, frac] = String.split(time_string, ".")

    with {:ok, base_ms} <- parse_hms(hms),
         {frac_ms, ""} <- Integer.parse(pad_or_trim_fraction(frac)) do
      {:ok, base_ms + frac_ms}
    else
      _ -> :error
    end
  end

  defp parse_hms(time_string) do
    parts = String.split(time_string, ":")

    case Enum.map(parts, &Integer.parse/1) do
      [{h, ""}, {m, ""}, {s, ""}] when m in 0..59 and s in 0..59 ->
        {:ok, (h * 3600 + m * 60 + s) * 1000}

      _ ->
        :error
    end
  end

  defp parse_ms(time_string) do
    parts = String.split(time_string, ":")

    case Enum.map(parts, &Integer.parse/1) do
      [{m, ""}, {s, ""}] when s in 0..59 ->
        {:ok, (m * 60 + s) * 1000}

      _ ->
        :error
    end
  end

  # Normalise fractional seconds to exactly 3 digits (milliseconds).
  defp pad_or_trim_fraction(frac) do
    cond do
      String.length(frac) == 3 -> frac
      String.length(frac) < 3 -> String.pad_trailing(frac, 3, "0")
      String.length(frac) > 3 -> String.slice(frac, 0, 3)
    end
  end

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
