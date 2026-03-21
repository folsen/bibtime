defmodule Bibtime.Results.Export do
  @moduledoc """
  Exports race results in various formats.
  """

  use Gettext, backend: BibtimeWeb.Gettext
  alias Bibtime.Results.Calculator

  @doc """
  Converts a list of ParticipantResult structs to a CSV string.
  """
  def to_csv(results, splits, opts \\ []) do
    has_auto_categories = Keyword.get(opts, :has_auto_categories, false)
    header = build_header(splits, has_auto_categories)
    rows = Enum.map(results, &build_row(&1, splits, has_auto_categories))

    [header | rows]
    |> Enum.map(&Enum.join(&1, ","))
    |> Enum.join("\r\n")
  end

  defp build_header(splits, has_auto_categories) do
    base = [
      gettext("Rank"),
      gettext("Bib"),
      gettext("First Name"),
      gettext("Last Name"),
      gettext("Club"),
      gettext("Category")
    ]

    auto_cols =
      if has_auto_categories,
        do: [gettext("Gender Category"), gettext("Age Group")],
        else: []

    split_cols = Enum.map(splits, & &1.short_name)
    base ++ auto_cols ++ split_cols ++ [gettext("Total"), gettext("Status")]
  end

  defp build_row(result, splits, has_auto_categories) do
    rank = if result.status == :finished, do: result.rank, else: ""

    base = [
      rank,
      result.participant.bib_number,
      escape_csv(result.participant.first_name),
      escape_csv(result.participant.last_name),
      escape_csv(result.participant.club || ""),
      escape_csv(if(result.category, do: result.category.name, else: ""))
    ]

    auto_cols =
      if has_auto_categories do
        auto_cats = result.auto_categories || []
        gender_cat = Enum.find(auto_cats, &(&1.type == :gender))
        age_cat = Enum.find(auto_cats, &(&1.type == :age_group))

        [
          escape_csv(if(gender_cat, do: gender_cat.name, else: "")),
          escape_csv(if(age_cat, do: age_cat.name, else: ""))
        ]
      else
        []
      end

    base = base ++ auto_cols

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
