defmodule Bibtime.Results.PdfTemplate do
  @moduledoc """
  Generates styled HTML for PDF export of race results.
  """

  use Gettext, backend: BibtimeWeb.Gettext
  alias Bibtime.Results.Calculator

  @doc """
  Renders a complete HTML document for race results, styled for print/poster display.
  """
  def render(race, results, splits, opts \\ []) do
    has_auto_categories = Keyword.get(opts, :has_auto_categories, false)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{css()}</style>
    </head>
    <body>
      #{header_section(race)}
      #{stats_bar(results)}
      #{results_table(results, splits, has_auto_categories)}
      #{footer(race)}
    </body>
    </html>
    """
  end

  defp header_section(race) do
    date_str = if race.date, do: format_date(race.date), else: ""
    location_str = if race.location, do: race.location, else: ""

    subtitle =
      [date_str, location_str]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" \u2014 ")

    """
    <div class="header">
      <div class="accent-bar"></div>
      <h1>#{escape(race.name)}</h1>
      <p class="subtitle">#{escape(subtitle)}</p>
      <div class="badge">#{escape(gettext("Official Results"))}</div>
    </div>
    """
  end

  defp stats_bar(results) do
    total = length(results)
    finished = Enum.count(results, &(&1.status == :finished))

    """
    <div class="stats-bar">
      <div class="stat">
        <span class="stat-number">#{total}</span>
        <span class="stat-label">#{escape(gettext("Participants"))}</span>
      </div>
      <div class="stat">
        <span class="stat-number">#{finished}</span>
        <span class="stat-label">#{escape(gettext("Finished"))}</span>
      </div>
    </div>
    """
  end

  defp results_table(results, splits, has_auto_categories) do
    header = table_header(splits, has_auto_categories)
    rows = Enum.map(results, &table_row(&1, splits, has_auto_categories))

    """
    <table>
      <thead>#{header}</thead>
      <tbody>#{Enum.join(rows)}</tbody>
    </table>
    """
  end

  defp table_header(splits, has_auto_categories) do
    auto_cols =
      if has_auto_categories do
        """
        <th>#{escape(gettext("Gender"))}</th>
        <th>#{escape(gettext("Age Group"))}</th>
        """
      else
        ""
      end

    split_cols =
      Enum.map_join(splits, fn split ->
        "<th class=\"time\">#{escape(split.short_name)}</th>"
      end)

    """
    <tr>
      <th class="rank">#</th>
      <th class="bib">#{escape(gettext("Bib"))}</th>
      <th class="name">#{escape(gettext("Name"))}</th>
      <th>#{escape(gettext("Club"))}</th>
      <th>#{escape(gettext("Category"))}</th>
      #{auto_cols}
      #{split_cols}
      <th class="time total-col">#{escape(gettext("Total"))}</th>
      <th class="status-col">#{escape(gettext("Status"))}</th>
    </tr>
    """
  end

  defp table_row(result, splits, has_auto_categories) do
    rank = if result.status == :finished, do: result.rank, else: nil
    rank_class = rank_css_class(rank)

    auto_cols =
      if has_auto_categories do
        auto_cats = result.auto_categories || []
        gender_cat = Enum.find(auto_cats, &(&1.type == :gender))
        age_cat = Enum.find(auto_cats, &(&1.type == :age_group))

        """
        <td>#{escape(if(gender_cat, do: gender_cat.name, else: "\u2014"))}</td>
        <td>#{escape(if(age_cat, do: age_cat.name, else: "\u2014"))}</td>
        """
      else
        ""
      end

    split_cells =
      if result.status in [:dns, :dnf, :dsq] do
        Enum.map_join(splits, fn _split ->
          "<td class=\"time muted\">\u2014</td>"
        end)
      else
        Enum.map_join(splits, fn split ->
          time = Map.get(result.leg_times, split.id)
          formatted = Calculator.format_time(time)

          pace =
            Calculator.format_pace(time, split.distance_meters, split.pace_display)

          pace_html =
            if pace,
              do: "<br><span class=\"pace\">#{escape(pace)}</span>",
              else: ""

          "<td class=\"time\">#{escape(formatted)}#{pace_html}</td>"
        end)
      end

    total_cell =
      if result.status in [:dns, :dnf, :dsq] do
        "<td class=\"time total-col muted\">\u2014</td>"
      else
        "<td class=\"time total-col\"><strong>#{escape(Calculator.format_time(result.total_ms))}</strong></td>"
      end

    status_html = status_badge(result.status)

    row_class =
      cond do
        rank == 1 -> "gold"
        rank == 2 -> "silver"
        rank == 3 -> "bronze"
        result.status in [:dns, :dnf, :dsq] -> "inactive"
        true -> ""
      end

    """
    <tr class="#{row_class}">
      <td class="rank #{rank_class}">#{rank_display(rank)}</td>
      <td class="bib">#{escape(to_string(result.participant.bib_number))}</td>
      <td class="name">#{escape(result.participant.first_name)} #{escape(result.participant.last_name)}</td>
      <td>#{escape(result.participant.club || "\u2014")}</td>
      <td>#{category_badge(result.category)}</td>
      #{auto_cols}
      #{split_cells}
      #{total_cell}
      <td class="status-col">#{status_html}</td>
    </tr>
    """
  end

  defp rank_display(nil), do: "\u2014"

  defp rank_display(1), do: "<span class=\"medal\">\u{1F947}</span>"
  defp rank_display(2), do: "<span class=\"medal\">\u{1F948}</span>"
  defp rank_display(3), do: "<span class=\"medal\">\u{1F949}</span>"
  defp rank_display(n), do: to_string(n)

  defp rank_css_class(1), do: "rank-1"
  defp rank_css_class(2), do: "rank-2"
  defp rank_css_class(3), do: "rank-3"
  defp rank_css_class(_), do: ""

  defp category_badge(nil), do: "<span class=\"muted\">\u2014</span>"

  defp category_badge(category) do
    "<span class=\"cat-badge\">#{escape(category.name)}</span>"
  end

  defp status_badge(:finished) do
    "<span class=\"status-badge finished\">#{escape(gettext("Finished"))}</span>"
  end

  defp status_badge(:racing) do
    "<span class=\"status-badge racing\">#{escape(gettext("Racing"))}</span>"
  end

  defp status_badge(:dns), do: "<span class=\"status-badge dns\">DNS</span>"
  defp status_badge(:dnf), do: "<span class=\"status-badge dnf\">DNF</span>"
  defp status_badge(:dsq), do: "<span class=\"status-badge dsq\">DSQ</span>"

  defp status_badge(status) do
    "<span class=\"status-badge\">#{escape(to_string(status))}</span>"
  end

  defp footer(race) do
    date_str = if race.date, do: format_date(race.date), else: ""

    """
    <div class="footer">
      <span>#{escape(race.name)} #{escape(date_str)}</span>
      <span>#{escape(gettext("Powered by BibTime"))}</span>
    </div>
    """
  end

  defp format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_date(_), do: ""

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape(other), do: escape(to_string(other))

  defp css do
    ~S"""
    @page {
      size: A4 landscape;
      margin: 12mm 10mm;
    }

    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      color: #1a1a2e;
      font-size: 9pt;
      line-height: 1.4;
      background: #fff;
    }

    .header {
      text-align: center;
      margin-bottom: 16px;
      padding-bottom: 14px;
      border-bottom: 2px solid #e0e0e0;
      position: relative;
    }

    .accent-bar {
      height: 5px;
      background: linear-gradient(90deg, #6366f1, #8b5cf6, #a78bfa, #c084fc);
      border-radius: 3px;
      margin-bottom: 14px;
    }

    .header h1 {
      font-size: 22pt;
      font-weight: 800;
      letter-spacing: -0.5px;
      color: #1a1a2e;
      margin-bottom: 4px;
    }

    .header .subtitle {
      font-size: 10pt;
      color: #64748b;
      margin-bottom: 8px;
    }

    .badge {
      display: inline-block;
      background: linear-gradient(135deg, #6366f1, #8b5cf6);
      color: white;
      font-size: 8pt;
      font-weight: 700;
      letter-spacing: 1.5px;
      text-transform: uppercase;
      padding: 4px 16px;
      border-radius: 20px;
    }

    .stats-bar {
      display: flex;
      justify-content: center;
      gap: 32px;
      margin-bottom: 14px;
    }

    .stat {
      display: flex;
      align-items: baseline;
      gap: 6px;
    }

    .stat-number {
      font-size: 16pt;
      font-weight: 800;
      color: #6366f1;
    }

    .stat-label {
      font-size: 8pt;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: #94a3b8;
    }

    /* Table */
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 8.5pt;
    }

    thead tr {
      background: #1e1b4b;
      color: white;
    }

    thead th {
      padding: 7px 6px;
      font-weight: 700;
      font-size: 7pt;
      text-transform: uppercase;
      letter-spacing: 0.8px;
      text-align: left;
      white-space: nowrap;
    }

    thead th:first-child { border-radius: 6px 0 0 0; }
    thead th:last-child { border-radius: 0 6px 0 0; }

    thead th.time { text-align: right; }
    thead th.rank { text-align: center; width: 42px; }
    thead th.bib { width: 40px; }
    thead th.status-col { text-align: center; }

    tbody tr {
      border-bottom: 1px solid #f1f5f9;
    }

    tbody tr:nth-child(even) {
      background: #f8fafc;
    }

    tbody tr:hover {
      background: #f1f5f9;
    }

    /* Podium rows */
    tr.gold { background: linear-gradient(90deg, #fef9c3 0%, #fef08a 15%, #fefce8 40%, transparent 60%) !important; }
    tr.silver { background: linear-gradient(90deg, #f1f5f9 0%, #e2e8f0 15%, #f8fafc 40%, transparent 60%) !important; }
    tr.bronze { background: linear-gradient(90deg, #fed7aa 0%, #fdba74 15%, #fff7ed 40%, transparent 60%) !important; }

    tr.inactive { opacity: 0.55; }

    td {
      padding: 5px 6px;
      vertical-align: middle;
    }

    td.rank {
      text-align: center;
      font-weight: 700;
      font-size: 9pt;
      color: #64748b;
    }

    td.rank.rank-1 { color: #b45309; font-size: 11pt; }
    td.rank.rank-2 { color: #475569; font-size: 11pt; }
    td.rank.rank-3 { color: #9a3412; font-size: 11pt; }

    td.bib {
      font-family: "SF Mono", "Cascadia Code", "Fira Code", monospace;
      font-weight: 600;
      color: #6366f1;
      font-size: 8.5pt;
    }

    td.name {
      font-weight: 600;
      white-space: nowrap;
    }

    td.time {
      text-align: right;
      font-family: "SF Mono", "Cascadia Code", "Fira Code", monospace;
      font-size: 8pt;
      white-space: nowrap;
    }

    td.total-col {
      font-size: 9pt;
    }

    td.status-col {
      text-align: center;
    }

    .pace {
      font-size: 6.5pt;
      color: #94a3b8;
    }

    .muted {
      color: #cbd5e1;
    }

    .medal {
      font-size: 13pt;
      line-height: 1;
    }

    .cat-badge {
      display: inline-block;
      background: #ede9fe;
      color: #6366f1;
      font-size: 7pt;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 10px;
    }

    .status-badge {
      display: inline-block;
      font-size: 6.5pt;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      padding: 2px 8px;
      border-radius: 10px;
    }

    .status-badge.finished { background: #dcfce7; color: #166534; }
    .status-badge.racing { background: #dbeafe; color: #1e40af; }
    .status-badge.dns { background: #fef3c7; color: #92400e; }
    .status-badge.dnf { background: #fee2e2; color: #991b1b; }
    .status-badge.dsq { background: #fee2e2; color: #991b1b; }

    .footer {
      margin-top: 16px;
      padding-top: 10px;
      border-top: 1px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      font-size: 7pt;
      color: #94a3b8;
    }
    """
  end
end
