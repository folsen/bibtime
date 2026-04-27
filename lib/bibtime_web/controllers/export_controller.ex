defmodule BibtimeWeb.ExportController do
  use BibtimeWeb, :controller

  alias Bibtime.Races
  alias Bibtime.Results
  alias Bibtime.Results.Export

  def results_pdf(conn, %{"slug" => slug}) do
    race =
      slug
      |> Races.get_visible_race_by_slug!(conn.assigns.current_scope)
      |> Bibtime.Repo.preload([:splits, :categories, :auto_categories])

    results = Results.get_race_results(race.id)
    splits = Races.list_splits(race.id)

    {:ok, pdf_base64} =
      Export.to_pdf(race, results, splits,
        has_manual_categories: race.categories != [],
        has_auto_categories: race.auto_categories != []
      )

    pdf_binary = Base.decode64!(pdf_base64)

    filename =
      race.slug
      |> String.replace(~r/[^a-z0-9-]/, "-")
      |> Kernel.<>("-results.pdf")

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, pdf_binary)
  end

  def results_csv(conn, %{"slug" => slug}) do
    race =
      slug
      |> Races.get_visible_race_by_slug!(conn.assigns.current_scope)
      |> Bibtime.Repo.preload([:splits, :categories, :auto_categories])

    results = Results.get_race_results(race.id)
    splits = Races.list_splits(race.id)

    csv =
      Export.to_csv(results, splits,
        has_manual_categories: race.categories != [],
        has_auto_categories: race.auto_categories != []
      )

    filename =
      race.slug
      |> String.replace(~r/[^a-z0-9-]/, "-")
      |> Kernel.<>("-results.csv")

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> send_resp(200, csv)
  end
end
