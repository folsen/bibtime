defmodule Bibtime.Results.Export do
  @moduledoc """
  Exports race results in various formats.
  """

  alias Bibtime.Results.Calculator

  @doc """
  Converts a list of ParticipantResult structs to a CSV string.
  """
  def to_csv(results, splits) do
    header = build_header(splits)
    rows = Enum.map(results, &build_row(&1, splits))

    [header | rows]
    |> Enum.map(&Enum.join(&1, ","))
    |> Enum.join("\r\n")
  end

  defp build_header(splits) do
    base = ["Rank", "Bib", "First Name", "Last Name", "Club", "Category"]
    split_cols = Enum.map(splits, & &1.short_name)
    base ++ split_cols ++ ["Total", "Status"]
  end

  defp build_row(result, splits) do
    rank = if result.status == :finished, do: result.rank, else: ""

    base = [
      rank,
      result.participant.bib_number,
      escape_csv(result.participant.first_name),
      escape_csv(result.participant.last_name),
      escape_csv(result.participant.club || ""),
      escape_csv(if(result.category, do: result.category.name, else: ""))
    ]

    split_times =
      Enum.map(splits, fn split ->
        Calculator.format_time(Map.get(result.leg_times, split.id))
      end)

    total = Calculator.format_time(result.total_ms)

    status =
      result.status
      |> Atom.to_string()
      |> String.upcase()

    base ++ split_times ++ [total, status]
  end

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end

  defp escape_csv(value), do: to_string(value)
end
