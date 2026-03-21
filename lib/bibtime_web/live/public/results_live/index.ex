defmodule BibtimeWeb.Public.ResultsLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Results
  alias Bibtime.Results.Calculator
  alias Bibtime.Results.Ranker

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :auto_categories, :splits])

    results = Results.get_race_results(race.id)
    splits = Races.list_splits(race.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")
    end

    {:ok,
     assign(socket,
       race: race,
       results: results,
       splits: splits,
       categories: race.categories,
       auto_categories: race.auto_categories,
       gender_auto_categories: Enum.filter(race.auto_categories, &(&1.type == :gender)),
       age_group_auto_categories: Enum.filter(race.auto_categories, &(&1.type == :age_group)),
       selected_category: nil,
       selected_auto_category: nil,
       filtered_results: results,
       recently_finished: MapSet.new(),
       sort_by: "rank",
       sort_dir: :asc,
       page_title: "Results - #{race.name}"
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category_param = params["category"]

    {selected_category, selected_auto_category, filtered_results} =
      case parse_category_param(category_param) do
        {:manual, cat_id} ->
          category = Enum.find(socket.assigns.categories, &(&1.id == cat_id))

          filtered =
            socket.assigns.results
            |> Enum.filter(fn r -> r.category != nil and r.category.id == cat_id end)
            |> Ranker.rank_results()

          {category, nil, filtered}

        {:auto, auto_cat_id} ->
          auto_cat = Enum.find(socket.assigns.auto_categories, &(&1.id == auto_cat_id))

          filtered =
            socket.assigns.results
            |> Enum.filter(fn r ->
              Enum.any?(r.auto_categories, &(&1.id == auto_cat_id))
            end)
            |> Ranker.rank_results()

          {nil, auto_cat, filtered}

        nil ->
          {nil, nil, socket.assigns.results}
      end

    # Reset sort to default rank when switching categories
    filtered_results = sort_results(filtered_results, "rank", :asc, socket.assigns.splits)

    {:noreply,
     assign(socket,
       selected_category: selected_category,
       selected_auto_category: selected_auto_category,
       filtered_results: filtered_results,
       sort_by: "rank",
       sort_dir: :asc
     )}
  end

  defp parse_category_param(nil), do: nil
  defp parse_category_param("auto:" <> id), do: {:auto, String.to_integer(id)}
  defp parse_category_param("manual:" <> id), do: {:manual, String.to_integer(id)}
  defp parse_category_param(id), do: {:manual, String.to_integer(id)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="mb-8 flex items-start gap-4">
        <div class="w-1 self-stretch rounded-full bg-gradient-to-b from-primary via-secondary to-accent shrink-0">
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-3 mb-1">
            <.link
              navigate={~p"/races/#{@race.slug}"}
              class="flex items-center justify-center w-8 h-8 rounded-full bg-base-200 text-base-content/50 hover:text-base-content hover:bg-base-300 transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-4" />
            </.link>
            <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content truncate">
              {@race.name}
            </h1>
            <span class={[
              "inline-flex items-center shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold tracking-wide uppercase",
              status_pill_class(@race.status)
            ]}>
              {format_race_status(@race.status)}
            </span>
          </div>
          <p class="text-sm text-base-content/50 ml-11">
            {if @race.date, do: Calendar.strftime(@race.date, "%B %d, %Y"), else: ""}
            {if @race.location, do: " \u2014 #{@race.location}", else: ""}
          </p>
        </div>
      </div>

      <%!-- Category filter tabs --%>
      <div class="flex flex-wrap items-center gap-2 mb-6" role="tablist">
        <.link
          patch={~p"/races/#{@race.slug}/results"}
          class={[
            "inline-flex items-center rounded-full px-4 py-1.5 text-sm font-medium transition-all duration-200",
            if(no_category_selected?(assigns),
              do: "bg-primary text-primary-content shadow-sm",
              else: "bg-base-200/60 text-base-content/60 hover:bg-base-300 hover:text-base-content"
            )
          ]}
          role="tab"
          aria-selected={no_category_selected?(assigns)}
        >
          Overall
        </.link>
        <%= if @categories != [] do %>
          <.link
            :for={category <- @categories}
            patch={~p"/races/#{@race.slug}/results?category=manual:#{category.id}"}
            class={[
              "inline-flex items-center rounded-full px-4 py-1.5 text-sm font-medium transition-all duration-200",
              if(@selected_category && @selected_category.id == category.id,
                do: "bg-primary text-primary-content shadow-sm",
                else: "bg-base-200/60 text-base-content/60 hover:bg-base-300 hover:text-base-content"
              )
            ]}
            role="tab"
            aria-selected={@selected_category && @selected_category.id == category.id}
          >
            {category.name}
          </.link>
        <% end %>
        <%= if @gender_auto_categories != [] do %>
          <span
            :if={@categories != []}
            class="w-px h-6 bg-base-300/60 mx-1"
          />
          <.link
            :for={auto_cat <- @gender_auto_categories}
            patch={~p"/races/#{@race.slug}/results?category=auto:#{auto_cat.id}"}
            class={[
              "inline-flex items-center rounded-full px-4 py-1.5 text-sm font-medium transition-all duration-200",
              if(@selected_auto_category && @selected_auto_category.id == auto_cat.id,
                do: "bg-primary text-primary-content shadow-sm",
                else: "bg-base-200/60 text-base-content/60 hover:bg-base-300 hover:text-base-content"
              )
            ]}
            role="tab"
            aria-selected={@selected_auto_category && @selected_auto_category.id == auto_cat.id}
          >
            {auto_cat.name}
          </.link>
        <% end %>
        <%= if @age_group_auto_categories != [] do %>
          <span
            :if={@categories != [] || @gender_auto_categories != []}
            class="w-px h-6 bg-base-300/60 mx-1"
          />
          <.link
            :for={auto_cat <- @age_group_auto_categories}
            patch={~p"/races/#{@race.slug}/results?category=auto:#{auto_cat.id}"}
            class={[
              "inline-flex items-center rounded-full px-4 py-1.5 text-sm font-medium transition-all duration-200",
              if(@selected_auto_category && @selected_auto_category.id == auto_cat.id,
                do: "bg-primary text-primary-content shadow-sm",
                else: "bg-base-200/60 text-base-content/60 hover:bg-base-300 hover:text-base-content"
              )
            ]}
            role="tab"
            aria-selected={@selected_auto_category && @selected_auto_category.id == auto_cat.id}
          >
            {auto_cat.name}
          </.link>
        <% end %>
      </div>

      <%!-- Results table --%>
      <div class="overflow-x-auto rounded-xl border border-base-300/50 bg-base-100">
        <table class="w-full border-separate border-spacing-0">
          <thead>
            <tr class="text-xs uppercase tracking-wider text-base-content/50">
              <th
                phx-click="sort" phx-value-col="rank"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-14 text-center px-3 py-3 font-semibold border-b border-base-300/50 first:rounded-tl-xl cursor-pointer hover:text-base-content select-none"
              >
                #<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="rank" />
              </th>
              <th
                phx-click="sort" phx-value-col="bib"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-16 px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                Bib<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="bib" />
              </th>
              <th
                phx-click="sort" phx-value-col="name"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                Name<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="name" />
              </th>
              <th
                phx-click="sort" phx-value-col="club"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                Club<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="club" />
              </th>
              <th
                :if={no_category_selected?(assigns)}
                phx-click="sort" phx-value-col="category"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                Category<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="category" />
              </th>
              <th
                :for={split <- @splits}
                phx-click="sort" phx-value-col={"split:#{split.id}"}
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-right cursor-pointer hover:text-base-content select-none"
              >
                {split.short_name}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col={"split:#{split.id}"} />
              </th>
              <th
                phx-click="sort" phx-value-col="total"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-bold border-b border-base-300/50 text-right cursor-pointer hover:text-base-content select-none"
              >
                Total<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="total" />
              </th>
              <th
                phx-click="sort" phx-value-col="status"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-20 px-3 py-3 font-semibold border-b border-base-300/50 text-center last:rounded-tr-xl cursor-pointer hover:text-base-content select-none"
              >
                Status<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="status" />
              </th>
            </tr>
          </thead>
          <tbody id="results-table">
            <tr
              :for={result <- @filtered_results}
              id={"result-#{result.participant.id}"}
              class={[
                "results-row even:bg-base-200/30 hover:bg-base-200/60 transition-colors",
                MapSet.member?(@recently_finished, result.participant.id) &&
                  "animate-pulse bg-success/15"
              ]}
            >
              <td class="text-center px-3 py-2.5 border-b border-base-300/20">
                <span :if={display_rank(result)} class={rank_class(display_rank(result))}>
                  {display_rank(result)}
                </span>
                <span
                  :if={display_rank(result) == nil && result.status in [:dns, :dnf, :dsq]}
                  class="text-base-content/30"
                >
                  &mdash;
                </span>
              </td>
              <td class="font-mono text-sm px-3 py-2.5 border-b border-base-300/20 text-base-content/70">
                {result.participant.bib_number}
              </td>
              <td class="font-medium px-3 py-2.5 border-b border-base-300/20 text-base-content">
                {result.participant.first_name} {result.participant.last_name}
              </td>
              <td class="text-base-content/50 text-sm px-3 py-2.5 border-b border-base-300/20">
                {result.participant.club || "\u2014"}
              </td>
              <td
                :if={no_category_selected?(assigns)}
                class="text-sm px-3 py-2.5 border-b border-base-300/20"
              >
                <span
                  :if={result.category}
                  class="inline-flex items-center rounded-full bg-primary/8 text-primary/80 px-2 py-0.5 text-xs font-medium"
                >
                  {result.category.name}
                </span>
                <span :if={result.category == nil} class="text-base-content/30">&mdash;</span>
              </td>
              <%= if result.status in [:dns, :dnf, :dsq] do %>
                <td
                  :for={_split <- @splits}
                  class="text-right font-mono text-sm px-3 py-2.5 border-b border-base-300/20 text-base-content/25"
                >
                  &mdash;
                </td>
                <td class="text-right font-mono text-sm px-3 py-2.5 border-b border-base-300/20 text-base-content/25">
                  &mdash;
                </td>
              <% else %>
                <td
                  :for={split <- @splits}
                  class="text-right font-mono text-sm px-3 py-2.5 border-b border-base-300/20 text-base-content/70"
                >
                  {Calculator.format_time(Map.get(result.leg_times, split.id))}
                </td>
                <td class="text-right font-mono text-base font-bold px-3 py-2.5 border-b border-base-300/20 text-base-content">
                  {Calculator.format_time(result.total_ms)}
                </td>
              <% end %>
              <td class="text-center px-3 py-2.5 border-b border-base-300/20">
                <span
                  :if={result.status == :dns}
                  class="inline-flex items-center rounded-full bg-warning/15 text-warning px-2 py-0.5 text-xs font-semibold"
                >
                  DNS
                </span>
                <span
                  :if={result.status == :dnf}
                  class="inline-flex items-center rounded-full bg-error/15 text-error px-2 py-0.5 text-xs font-semibold"
                >
                  DNF
                </span>
                <span
                  :if={result.status == :dsq}
                  class="inline-flex items-center rounded-full bg-error/15 text-error px-2 py-0.5 text-xs font-semibold"
                >
                  DSQ
                </span>
                <span
                  :if={result.status == :finished}
                  class="inline-flex items-center rounded-full bg-success/15 text-success px-2 py-0.5 text-xs font-semibold"
                >
                  Finished
                </span>
                <span
                  :if={result.status == :racing}
                  class="inline-flex items-center rounded-full bg-info/15 text-info px-2 py-0.5 text-xs font-semibold"
                >
                  Racing
                </span>
                <span
                  :if={result.status == :registered}
                  class="inline-flex items-center rounded-full bg-base-content/10 text-base-content/60 px-2 py-0.5 text-xs font-semibold"
                >
                  Registered
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Empty state --%>
      <div :if={@filtered_results == []} class="text-center py-16">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
          <.icon name="hero-clock" class="size-8 text-base-content/30" />
        </div>
        <p class="text-lg font-medium text-base-content/50 mb-1">No results yet</p>
        <p class="text-sm text-base-content/40">Results will appear here once timing begins.</p>
      </div>

      <%!-- Stats footer --%>
      <div :if={@filtered_results != []} class="mt-6 flex flex-wrap items-center gap-3">
        <div class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2">
          <.icon name="hero-users" class="size-4 text-primary/60" />
          <span class="text-sm font-medium text-base-content/70">
            {length(@filtered_results)} participant{if length(@filtered_results) != 1,
              do: "s",
              else: ""}
          </span>
        </div>
        <div class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2">
          <.icon name="hero-check-circle" class="size-4 text-success/60" />
          <span class="text-sm font-medium text-base-content/70">
            {Enum.count(@filtered_results, &(&1.status == :finished))} finished
          </span>
        </div>
        <div
          :if={Enum.any?(@filtered_results, &(&1.status == :racing))}
          class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2"
        >
          <.icon name="hero-arrow-path" class="size-4 text-info/60" />
          <span class="text-sm font-medium text-base-content/70">
            {Enum.count(@filtered_results, &(&1.status == :racing))} still racing
          </span>
        </div>
        <div class="ml-auto flex items-center gap-2">
          <a
            href={~p"/races/#{@race.slug}/kiosk"}
            target="_blank"
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-tv" class="size-4" /> Kiosk
          </a>
          <a
            href={~p"/races/#{@race.slug}/results/export/csv"}
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
          </a>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("sort", %{"col" => col}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col do
        {col, toggle_dir(socket.assigns.sort_dir)}
      else
        {col, :asc}
      end

    filtered_results = sort_results(socket.assigns.filtered_results, sort_by, sort_dir, socket.assigns.splits)

    {:noreply, assign(socket, sort_by: sort_by, sort_dir: sort_dir, filtered_results: filtered_results)}
  end

  @impl true
  def handle_info({:split_time_recorded, _split_time}, socket) do
    old_finished_ids =
      socket.assigns.filtered_results
      |> Enum.filter(&(&1.status == :finished))
      |> MapSet.new(& &1.participant.id)

    socket = recalculate_results(socket)

    new_finished_ids =
      socket.assigns.filtered_results
      |> Enum.filter(&(&1.status == :finished))
      |> MapSet.new(& &1.participant.id)

    newly_finished = MapSet.difference(new_finished_ids, old_finished_ids)

    Enum.each(newly_finished, fn participant_id ->
      Process.send_after(self(), {:clear_highlight, participant_id}, 10_000)
    end)

    recently_finished = MapSet.union(socket.assigns.recently_finished, newly_finished)

    {:noreply, assign(socket, recently_finished: recently_finished)}
  end

  @impl true
  def handle_info({:clear_highlight, participant_id}, socket) do
    recently_finished = MapSet.delete(socket.assigns.recently_finished, participant_id)
    {:noreply, assign(socket, recently_finished: recently_finished)}
  end

  @impl true
  def handle_info({:split_time_deleted, _split_time}, socket) do
    {:noreply, recalculate_results(socket)}
  end

  defp recalculate_results(socket) do
    race = socket.assigns.race
    results = Results.get_race_results(race.id)

    filtered_results =
      cond do
        socket.assigns.selected_category ->
          category = socket.assigns.selected_category

          results
          |> Enum.filter(fn r -> r.category != nil and r.category.id == category.id end)
          |> Ranker.rank_results()

        socket.assigns.selected_auto_category ->
          auto_cat = socket.assigns.selected_auto_category

          results
          |> Enum.filter(fn r ->
            Enum.any?(r.auto_categories, &(&1.id == auto_cat.id))
          end)
          |> Ranker.rank_results()

        true ->
          results
      end

    filtered_results = sort_results(filtered_results, socket.assigns.sort_by, socket.assigns.sort_dir, socket.assigns.splits)

    assign(socket, results: results, filtered_results: filtered_results)
  end

  defp no_category_selected?(assigns) do
    assigns.selected_category == nil and assigns.selected_auto_category == nil
  end

  defp display_rank(result) do
    if result.status == :finished, do: result.rank, else: nil
  end

  defp rank_class(rank) when rank == 1 do
    "inline-flex items-center justify-center w-7 h-7 rounded-full bg-warning/20 text-warning font-bold text-sm font-mono"
  end

  defp rank_class(rank) when rank == 2 do
    "inline-flex items-center justify-center w-7 h-7 rounded-full bg-base-300/60 text-base-content/70 font-bold text-sm font-mono"
  end

  defp rank_class(rank) when rank == 3 do
    "inline-flex items-center justify-center w-7 h-7 rounded-full bg-secondary/15 text-secondary font-bold text-sm font-mono"
  end

  defp rank_class(_rank) do
    "font-mono text-sm text-base-content/60"
  end

  defp status_pill_class(status) do
    case status do
      :draft -> "bg-base-300/50 text-base-content/60"
      :registration_open -> "bg-info/15 text-info"
      :registration_closed -> "bg-warning/15 text-warning"
      :in_progress -> "bg-success/15 text-success"
      :finished -> "bg-accent/15 text-accent"
      :archived -> "bg-neutral/15 text-neutral"
      _ -> "bg-base-300/50 text-base-content/60"
    end
  end

  defp format_race_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_results(results, sort_by, sort_dir, _splits) do
    sorted =
      case sort_by do
        "rank" ->
          Enum.sort_by(results, fn r -> r.rank || 999_999 end)

        "bib" ->
          Enum.sort_by(results, fn r ->
            case Integer.parse(r.participant.bib_number || "") do
              {n, _} -> n
              :error -> 999_999
            end
          end)

        "name" ->
          Enum.sort_by(results, fn r ->
            String.downcase("#{r.participant.last_name} #{r.participant.first_name}")
          end)

        "club" ->
          Enum.sort_by(results, fn r ->
            String.downcase(r.participant.club || "zzz")
          end)

        "category" ->
          Enum.sort_by(results, fn r ->
            if r.category, do: String.downcase(r.category.name), else: "zzz"
          end)

        "total" ->
          Enum.sort_by(results, fn r -> r.total_ms || 999_999_999 end)

        "status" ->
          Enum.sort_by(results, fn r -> Atom.to_string(r.status) end)

        "split:" <> split_id_str ->
          split_id = String.to_integer(split_id_str)

          Enum.sort_by(results, fn r ->
            Map.get(r.leg_times || %{}, split_id) || 999_999_999
          end)

        _ ->
          results
      end

    if sort_dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_indicator(assigns) do
    ~H"""
    <span :if={@sort_by == @col} class="ml-1 text-primary">
      <.icon :if={@sort_dir == :asc} name="hero-chevron-up-mini" class="size-3 inline" />
      <.icon :if={@sort_dir == :desc} name="hero-chevron-down-mini" class="size-3 inline" />
    </span>
    """
  end
end
