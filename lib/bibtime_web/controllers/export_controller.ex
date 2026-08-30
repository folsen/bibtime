defmodule BibtimeWeb.ExportController do
  use BibtimeWeb, :controller

  require Logger

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

    pdf =
      Export.to_pdf(race, results, splits,
        has_manual_categories: race.categories != [],
        has_auto_categories: race.auto_categories != []
      )

    case pdf do
      {:ok, pdf_base64} ->
        filename =
          race.slug
          |> String.replace(~r/[^a-z0-9-]/, "-")
          |> Kernel.<>("-results.pdf")

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
        |> send_resp(200, Base.decode64!(pdf_base64))

      {:error, reason} ->
        # A render failure is an operational problem, not something the
        # organizer can fix — log the detail, hand them the results page back
        # with a message rather than a bare 500.
        Logger.error("PDF export failed for race #{race.slug}: #{inspect(reason)}")

        conn
        |> put_flash(:error, gettext("Could not generate the PDF. Please try again."))
        |> redirect(to: ~p"/races/#{race.slug}/results")
    end
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
