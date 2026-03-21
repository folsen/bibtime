defmodule BibtimeWeb.Public.ProfileLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Results
  alias Bibtime.Results.Calculator

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    race_results = Results.get_user_race_results(user.id)

    stats = compute_stats(race_results)

    {:ok,
     assign(socket,
       race_results: race_results,
       stats: stats,
       expanded_race: nil,
       page_title: gettext("My Profile")
     )}
  end

  @impl true
  def handle_event("toggle-race", %{"race-id" => race_id}, socket) do
    race_id = String.to_integer(race_id)

    expanded =
      if socket.assigns.expanded_race == race_id, do: nil, else: race_id

    {:noreply, assign(socket, expanded_race: expanded)}
  end

  defp compute_stats(race_results) do
    total = length(race_results)

    finished =
      Enum.count(race_results, fn entry ->
        entry.result && entry.result.status == :finished
      end)

    podiums =
      Enum.count(race_results, fn entry ->
        entry.result && entry.result.status == :finished && entry.result.rank != nil &&
          entry.result.rank <= 3
      end)

    dns = Enum.count(race_results, fn e -> e.result && e.result.status == :dns end)
    dnf = Enum.count(race_results, fn e -> e.result && e.result.status == :dnf end)
    dsq = Enum.count(race_results, fn e -> e.result && e.result.status == :dsq end)

    %{
      total: total,
      finished: finished,
      podiums: podiums,
      dns: dns,
      dnf: dnf,
      dsq: dsq
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-10">
      <%!-- Header --%>
      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-base-content mb-2">
          {gettext("My Profile")}
        </h1>
        <p class="text-base-content/50">{gettext("Your race history and performance summary")}</p>
      </div>

      <%!-- Stats cards --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-10">
        <.stat_card label={gettext("Races")} value={@stats.total} icon="hero-flag" color="primary" />
        <.stat_card
          label={gettext("Finished")}
          value={@stats.finished}
          icon="hero-check-circle"
          color="success"
        />
        <.stat_card
          label={gettext("Podiums")}
          value={@stats.podiums}
          icon="hero-trophy"
          color="warning"
        />
        <.stat_card
          label={gettext("DNS / DNF")}
          value={@stats.dns + @stats.dnf}
          icon="hero-x-circle"
          color="error"
        />
      </div>

      <%!-- Race history --%>
      <h2 class="text-xl font-semibold text-base-content mb-4">{gettext("Race History")}</h2>

      <div
        :if={@race_results == []}
        class="rounded-xl bg-base-200/60 border border-base-300/50 px-8 py-12 text-center"
      >
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-300/50 mb-4">
          <.icon name="hero-clock" class="size-8 text-base-content/30" />
        </div>
        <h3 class="text-xl font-semibold text-base-content mb-2">{gettext("No races yet")}</h3>
        <p class="text-base-content/50">{gettext("Register for a race to see your results here.")}</p>
      </div>

      <div :if={@race_results != []} class="space-y-3">
        <div
          :for={entry <- @race_results}
          class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden"
        >
          <%!-- Race row (always visible) --%>
          <button
            phx-click="toggle-race"
            phx-value-race-id={entry.race.id}
            class="w-full px-5 py-4 flex items-center gap-4 hover:bg-base-200/40 transition-colors text-left"
          >
            <%!-- Rank badge --%>
            <div class={[
              "flex items-center justify-center w-12 h-12 rounded-2xl shrink-0 border",
              rank_badge_class(entry.result)
            ]}>
              <span :if={display_rank(entry.result)} class="text-lg font-bold font-mono">
                {display_rank(entry.result)}
              </span>
              <span :if={!display_rank(entry.result)} class="text-sm font-semibold">
                {format_status_short(entry.result)}
              </span>
            </div>

            <div class="flex-1 min-w-0">
              <h3 class="font-semibold text-base-content truncate">{entry.race.name}</h3>
              <div class="flex flex-wrap items-center gap-2 mt-0.5">
                <span :if={entry.race.date} class="text-sm text-base-content/50">
                  {format_date(entry.race.date)}
                </span>
                <span
                  :if={entry.result && entry.result.category}
                  class="inline-flex items-center rounded-full bg-primary/8 text-primary/80 px-2 py-0.5 text-xs font-medium"
                >
                  {entry.result.category.name}
                </span>
                <span :if={entry.category_rank} class="text-xs text-base-content/40">
                  {gettext("(#%{rank} in category)", rank: entry.category_rank)}
                </span>
              </div>
            </div>

            <div class="flex items-center gap-3 shrink-0">
              <span class="font-mono text-lg font-bold text-base-content">
                {if entry.result, do: Calculator.format_time(entry.result.total_ms), else: "--:--"}
              </span>
              <.icon
                name={
                  if @expanded_race == entry.race.id, do: "hero-chevron-up", else: "hero-chevron-down"
                }
                class="size-5 text-base-content/30"
              />
            </div>
          </button>

          <%!-- Expanded split breakdown --%>
          <div
            :if={@expanded_race == entry.race.id && entry.splits != [] && entry.result}
            class="border-t border-base-300/40 bg-base-200/30 px-5 py-4"
          >
            <div class="flex items-center justify-between mb-3">
              <span class="text-sm font-medium text-base-content/60 uppercase tracking-wider">
                {gettext("Split Breakdown")}
              </span>
              <.link
                navigate={~p"/races/#{entry.race.slug}/results"}
                class="text-sm text-primary hover:underline"
              >
                {gettext("View full results")}
              </.link>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="text-xs uppercase tracking-wider text-base-content/40">
                    <th class="text-left py-1.5 pr-4 font-semibold">{gettext("Split")}</th>
                    <th class="text-right py-1.5 pl-4 font-semibold">{gettext("Leg Time")}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={split <- entry.splits}
                    class="border-t border-base-300/30"
                  >
                    <td class="py-2 pr-4 text-base-content/70">{split.name}</td>
                    <td class="py-2 pl-4 text-right font-mono text-base-content">
                      {Calculator.format_time(Map.get(entry.result.leg_times, split.id))}
                    </td>
                  </tr>
                  <tr class="border-t-2 border-base-300/60 font-bold">
                    <td class="py-2 pr-4 text-base-content">{gettext("Total")}</td>
                    <td class="py-2 pl-4 text-right font-mono text-base-content">
                      {Calculator.format_time(entry.result.total_ms)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Auto-category ranks --%>
            <div
              :if={entry.result.auto_categories != []}
              class="mt-3 flex flex-wrap gap-2"
            >
              <span
                :for={auto_cat <- entry.result.auto_categories}
                class="inline-flex items-center rounded-full bg-base-300/50 px-2.5 py-0.5 text-xs font-medium text-base-content/60"
              >
                {auto_cat.name}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm px-4 py-4 text-center">
      <div class={[
        "inline-flex items-center justify-center w-10 h-10 rounded-full mb-2",
        stat_icon_bg(@color)
      ]}>
        <.icon name={@icon} class={["size-5", stat_icon_color(@color)]} />
      </div>
      <div class="text-2xl font-bold font-mono text-base-content">{@value}</div>
      <div class="text-xs font-medium text-base-content/50 uppercase tracking-wider mt-0.5">
        {@label}
      </div>
    </div>
    """
  end

  defp stat_icon_bg("primary"), do: "bg-primary/10"
  defp stat_icon_bg("success"), do: "bg-success/10"
  defp stat_icon_bg("warning"), do: "bg-warning/10"
  defp stat_icon_bg("error"), do: "bg-error/10"
  defp stat_icon_bg(_), do: "bg-base-300/50"

  defp stat_icon_color("primary"), do: "text-primary/70"
  defp stat_icon_color("success"), do: "text-success/70"
  defp stat_icon_color("warning"), do: "text-warning/70"
  defp stat_icon_color("error"), do: "text-error/70"
  defp stat_icon_color(_), do: "text-base-content/50"

  defp display_rank(nil), do: nil

  defp display_rank(result) do
    if result.status == :finished && result.rank, do: result.rank
  end

  defp rank_badge_class(nil), do: "bg-base-200/60 border-base-300/50 text-base-content/40"

  defp rank_badge_class(result) do
    cond do
      result.status == :finished && result.rank == 1 ->
        "bg-warning/15 border-warning/30 text-warning"

      result.status == :finished && result.rank == 2 ->
        "bg-base-300/60 border-base-300 text-base-content/70"

      result.status == :finished && result.rank == 3 ->
        "bg-secondary/10 border-secondary/25 text-secondary"

      result.status == :finished ->
        "bg-success/8 border-success/20 text-success"

      result.status in [:dns, :dnf, :dsq] ->
        "bg-error/8 border-error/20 text-error"

      true ->
        "bg-base-200/60 border-base-300/50 text-base-content/40"
    end
  end

  defp format_status_short(nil), do: "--"

  defp format_status_short(result) do
    case result.status do
      :dns -> "DNS"
      :dnf -> "DNF"
      :dsq -> "DSQ"
      :racing -> "..."
      :registered -> "REG"
      :finished -> "--"
      _ -> "--"
    end
  end
end
