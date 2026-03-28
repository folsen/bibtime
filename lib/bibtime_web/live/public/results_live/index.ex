defmodule BibtimeWeb.Public.ResultsLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Photos
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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")
    end

    socket =
      socket
      |> assign(
        race: race,
        results: [],
        splits: [],
        photo_count: 0,
        loading: true,
        categories: race.categories,
        auto_categories: race.auto_categories,
        gender_auto_categories: Enum.filter(race.auto_categories, &(&1.type == :gender)),
        age_group_auto_categories: Enum.filter(race.auto_categories, &(&1.type == :age_group)),
        selected_category: nil,
        selected_auto_category: nil,
        filtered_results: [],
        recently_finished: MapSet.new(),
        sort_by: "rank",
        sort_dir: :asc,
        page_title: gettext("Results") <> " - " <> race.name
      )

    socket =
      if connected?(socket) do
        race_id = race.id

        start_async(socket, :load_results_data, fn ->
          %{
            results: Results.get_race_results(race_id),
            splits: Races.list_splits(race_id),
            photo_count: Photos.count_photos(race_id)
          }
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category_param = params["category"]

    {selected_category, selected_auto_category} =
      case parse_category_param(category_param) do
        {:manual, cat_id} ->
          {Enum.find(socket.assigns.categories, &(&1.id == cat_id)), nil}

        {:auto, auto_cat_id} ->
          {nil, Enum.find(socket.assigns.auto_categories, &(&1.id == auto_cat_id))}

        nil ->
          {nil, nil}
      end

    {:noreply,
     socket
     |> assign(
       selected_category: selected_category,
       selected_auto_category: selected_auto_category,
       sort_by: "rank",
       sort_dir: :asc
     )
     |> apply_category_filter()}
  end

  @impl true
  def handle_async(:load_results_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(
       results: data.results,
       splits: data.splits,
       photo_count: data.photo_count,
       loading: false
     )
     |> apply_category_filter()}
  end

  @impl true
  def handle_async(:load_results_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
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
            <.status_pill
              status={@race.status}
              class="inline-flex items-center shrink-0 font-semibold tracking-wide uppercase"
            />
          </div>
          <p class="text-sm text-base-content/50 ml-11">
            {if @race.date, do: format_date(@race.date), else: ""}
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
          {gettext("Overall")}
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

      <%!-- Loading skeleton --%>
      <div :if={@loading} class="rounded-xl border border-base-300/50 bg-base-100 p-6">
        <div class="animate-pulse space-y-4">
          <div class="h-8 bg-base-200 rounded-lg w-full"></div>
          <div class="h-6 bg-base-200/60 rounded w-11/12"></div>
          <div class="h-6 bg-base-200/60 rounded w-full"></div>
          <div class="h-6 bg-base-200/60 rounded w-10/12"></div>
          <div class="h-6 bg-base-200/60 rounded w-full"></div>
          <div class="h-6 bg-base-200/60 rounded w-9/12"></div>
        </div>
      </div>

      <%!-- Results table --%>
      <div :if={!@loading} class="overflow-x-auto rounded-xl border border-base-300/50 bg-base-100">
        <table class="w-full border-separate border-spacing-0">
          <thead>
            <tr class="text-xs uppercase tracking-wider text-base-content/50">
              <th
                phx-click="sort"
                phx-value-col="rank"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-14 text-center px-3 py-3 font-semibold border-b border-base-300/50 first:rounded-tl-xl cursor-pointer hover:text-base-content select-none"
              >
                #<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="rank" />
              </th>
              <th
                phx-click="sort"
                phx-value-col="bib"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-16 px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Bib")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="bib" />
              </th>
              <th
                phx-click="sort"
                phx-value-col="name"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Name")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="name" />
              </th>
              <th
                phx-click="sort"
                phx-value-col="club"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Club")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="club" />
              </th>
              <th
                :if={no_category_selected?(assigns)}
                phx-click="sort"
                phx-value-col="category"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Category")}<.sort_indicator
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                  col="category"
                />
              </th>
              <th
                :for={split <- @splits}
                phx-click="sort"
                phx-value-col={"split:#{split.id}"}
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-right cursor-pointer hover:text-base-content select-none"
              >
                {split.short_name}<.sort_indicator
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                  col={"split:#{split.id}"}
                />
              </th>
              <th
                phx-click="sort"
                phx-value-col="total"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-bold border-b border-base-300/50 text-right cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Total")}<.sort_indicator
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                  col="total"
                />
              </th>
              <th
                phx-click="sort"
                phx-value-col="status"
                class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-20 px-3 py-3 font-semibold border-b border-base-300/50 text-center last:rounded-tr-xl cursor-pointer hover:text-base-content select-none"
              >
                {gettext("Status")}<.sort_indicator
                  sort_by={@sort_by}
                  sort_dir={@sort_dir}
                  col="status"
                />
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
                <.rank_badge :if={display_rank(result)} rank={display_rank(result)} />
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
                  <div>{Calculator.format_time(Map.get(result.leg_times, split.id))}</div>
                  <div
                    :if={
                      pace_text =
                        Calculator.format_pace(
                          Map.get(result.leg_times, split.id),
                          split.distance_meters,
                          split.pace_display
                        )
                    }
                    class="text-xs text-base-content/40"
                  >
                    {pace_text}
                  </div>
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
                  {format_participant_status(:finished)}
                </span>
                <span
                  :if={result.status == :racing}
                  class="inline-flex items-center rounded-full bg-info/15 text-info px-2 py-0.5 text-xs font-semibold"
                >
                  {format_participant_status(:racing)}
                </span>
                <span
                  :if={result.status == :registered}
                  class="inline-flex items-center rounded-full bg-base-content/10 text-base-content/60 px-2 py-0.5 text-xs font-semibold"
                >
                  {format_participant_status(:registered)}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Empty state --%>
      <div :if={!@loading and @filtered_results == []} class="text-center py-16">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
          <.icon name="hero-clock" class="size-8 text-base-content/30" />
        </div>
        <p class="text-lg font-medium text-base-content/50 mb-1">{gettext("No results yet")}</p>
        <p class="text-sm text-base-content/40">
          {gettext("Results will appear here once timing begins.")}
        </p>
      </div>

      <%!-- Stats footer --%>
      <div :if={!@loading and @filtered_results != []} class="mt-6 flex flex-wrap items-center gap-3">
        <div class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2">
          <.icon name="hero-users" class="size-4 text-primary/60" />
          <span class="text-sm font-medium text-base-content/70">
            {ngettext("%{count} participant", "%{count} participants", length(@filtered_results))}
          </span>
        </div>
        <div class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2">
          <.icon name="hero-check-circle" class="size-4 text-success/60" />
          <span class="text-sm font-medium text-base-content/70">
            {gettext("%{count} finished",
              count: Enum.count(@filtered_results, &(&1.status == :finished))
            )}
          </span>
        </div>
        <div
          :if={Enum.any?(@filtered_results, &(&1.status == :racing))}
          class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2"
        >
          <.icon name="hero-arrow-path" class="size-4 text-info/60" />
          <span class="text-sm font-medium text-base-content/70">
            {gettext("%{count} still racing",
              count: Enum.count(@filtered_results, &(&1.status == :racing))
            )}
          </span>
        </div>
        <div class="ml-auto flex items-center gap-2">
          <.link
            :if={@photo_count > 0}
            navigate={~p"/races/#{@race.slug}/photos"}
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-photo" class="size-4" />
            {ngettext("%{count} Photo", "%{count} Photos", @photo_count)}
          </.link>
          <a
            href={~p"/races/#{@race.slug}/kiosk"}
            target="_blank"
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-tv" class="size-4" /> {gettext("Kiosk")}
          </a>
          <a
            href={~p"/races/#{@race.slug}/results/export/pdf"}
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-document-text" class="size-4" /> {gettext("Export PDF")}
          </a>
          <a
            href={~p"/races/#{@race.slug}/results/export/csv"}
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Export CSV")}
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

    filtered_results =
      sort_results(socket.assigns.filtered_results, sort_by, sort_dir)

    {:noreply,
     assign(socket, sort_by: sort_by, sort_dir: sort_dir, filtered_results: filtered_results)}
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

    socket
    |> assign(results: results)
    |> apply_category_filter()
  end

  defp apply_category_filter(socket) do
    results = socket.assigns.results

    filtered_results =
      cond do
        socket.assigns.selected_category ->
          cat_id = socket.assigns.selected_category.id

          results
          |> Enum.filter(fn r -> r.category != nil and r.category.id == cat_id end)
          |> Ranker.rank_results()

        socket.assigns.selected_auto_category ->
          auto_cat_id = socket.assigns.selected_auto_category.id

          results
          |> Enum.filter(fn r ->
            Enum.any?(r.auto_categories, &(&1.id == auto_cat_id))
          end)
          |> Ranker.rank_results()

        true ->
          results
      end

    filtered_results =
      sort_results(filtered_results, socket.assigns.sort_by, socket.assigns.sort_dir)

    assign(socket, filtered_results: filtered_results)
  end

  defp no_category_selected?(assigns) do
    assigns.selected_category == nil and assigns.selected_auto_category == nil
  end

  defp display_rank(result) do
    if result.status == :finished, do: result.rank, else: nil
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_results(results, sort_by, sort_dir) do
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
