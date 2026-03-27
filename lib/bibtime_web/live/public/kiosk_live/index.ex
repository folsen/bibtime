defmodule BibtimeWeb.Public.KioskLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Results
  alias Bibtime.Results.Calculator
  alias Bibtime.Results.Ranker

  # Category rotation interval (ms)
  @rotation_interval_ms 15_000

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
        loading: true,
        categories: race.categories,
        auto_categories: race.auto_categories,
        filtered_results: [],
        recently_finished: MapSet.new(),
        current_category_label: gettext("Overall"),
        current_category_index: 0,
        rotation_enabled: false,
        rotation_timer: nil,
        scroll_speed: "normal",
        show_columns: MapSet.new(["rank", "bib", "name", "total", "status"]),
        page_title: "#{race.name} — Live Results"
      )

    socket =
      if connected?(socket) do
        race_id = race.id

        start_async(socket, :load_kiosk_data, fn ->
          %{
            results: Results.get_race_results(race_id),
            splits: Races.list_splits(race_id)
          }
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Parse URL params for configuration
    scroll_speed = params["scroll_speed"] || socket.assigns.scroll_speed
    theme = params["theme"]

    # Parse columns to show
    show_columns =
      case params["columns"] do
        nil ->
          socket.assigns.show_columns

        cols ->
          cols
          |> String.split(",")
          |> MapSet.new()
      end

    # Handle theme via push_event (client-side)
    socket =
      if connected?(socket) && theme in ["light", "dark"] do
        push_event(socket, "set-theme", %{theme: theme})
      else
        socket
      end

    # Handle category param or enable rotation
    {category_index, rotation_enabled, socket} =
      case params["category"] do
        nil ->
          # No category specified — enable rotation if there are categories to rotate through
          all_categories = build_category_list(socket.assigns)

          if length(all_categories) > 1 do
            {0, true, socket}
          else
            {0, false, socket}
          end

        "overall" ->
          {0, false, socket}

        category_param ->
          # Find category by param and lock to it (no rotation)
          all_categories = build_category_list(socket.assigns)

          index =
            Enum.find_index(all_categories, fn {_label, filter} ->
              match_category_param?(filter, category_param)
            end) || 0

          {index, false, socket}
      end

    # Cancel existing timer if any
    if socket.assigns.rotation_timer do
      Process.cancel_timer(socket.assigns.rotation_timer)
    end

    # Start rotation timer if enabled
    timer =
      if rotation_enabled && connected?(socket) do
        Process.send_after(self(), :rotate_category, @rotation_interval_ms)
      else
        nil
      end

    all_categories = build_category_list(socket.assigns)
    {label, _filter} = Enum.at(all_categories, category_index, {gettext("Overall"), nil})

    filtered = filter_by_index(socket.assigns.results, all_categories, category_index)

    {:noreply,
     assign(socket,
       scroll_speed: scroll_speed,
       show_columns: show_columns,
       current_category_index: category_index,
       current_category_label: label,
       rotation_enabled: rotation_enabled,
       rotation_timer: timer,
       filtered_results: filtered
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="kiosk-display"
      class="kiosk-display h-screen flex flex-col"
      phx-hook=".KioskScroll"
      data-scroll-speed={@scroll_speed}
    >
      <%!-- Kiosk header bar --%>
      <div class="kiosk-header flex items-center justify-between px-8 py-4 bg-base-200/80 border-b border-base-300/50 shrink-0">
        <div class="flex items-center gap-4">
          <span class="text-2xl font-bold tracking-tight text-primary">Bib</span><span class="text-2xl font-bold tracking-tight text-base-content">Time</span>
          <span class="w-px h-8 bg-base-300/60"></span>
          <h1 class="text-2xl font-bold text-base-content truncate">{@race.name}</h1>
        </div>
        <div class="flex items-center gap-6">
          <div class="flex items-center gap-2">
            <span class={[
              "inline-flex items-center rounded-full px-4 py-1.5 text-lg font-semibold",
              "bg-primary/15 text-primary"
            ]}>
              {@current_category_label}
            </span>
            <span
              :if={@rotation_enabled}
              class="text-base-content/40 text-sm"
            >
              (auto)
            </span>
          </div>
          <div class="flex items-center gap-3 text-base-content/50">
            <span class="inline-flex items-center gap-2 rounded-lg bg-base-300/40 px-3 py-1.5">
              <.icon name="hero-check-circle" class="size-5 text-success/70" />
              <span class="text-lg font-semibold">
                {Enum.count(@filtered_results, &(&1.status == :finished))}
              </span>
            </span>
            <span class="inline-flex items-center gap-2 rounded-lg bg-base-300/40 px-3 py-1.5">
              <.icon name="hero-users" class="size-5 text-primary/70" />
              <span class="text-lg font-semibold">
                {length(@filtered_results)}
              </span>
            </span>
          </div>
        </div>
      </div>

      <%!-- Loading state --%>
      <div :if={@loading} class="flex-1 min-h-0 flex items-center justify-center">
        <div class="text-center">
          <div class="loading loading-spinner loading-lg text-primary mb-4"></div>
          <p class="text-xl text-base-content/40">{gettext("Loading results...")}</p>
        </div>
      </div>

      <%!-- Scrollable results area --%>
      <div :if={!@loading} id="kiosk-scroll-area" class="flex-1 min-h-0 overflow-hidden">
        <table class="w-full border-separate border-spacing-0 kiosk-table">
          <thead>
            <tr class="text-lg uppercase tracking-wider text-base-content/50">
              <th
                :if={show_col?(@show_columns, "rank")}
                class="sticky top-0 z-10 bg-base-100 w-20 text-center px-6 py-4 font-semibold border-b-2 border-base-300/50"
              >
                #
              </th>
              <th
                :if={show_col?(@show_columns, "bib")}
                class="sticky top-0 z-10 bg-base-100 w-24 px-6 py-4 font-semibold border-b-2 border-base-300/50 text-left"
              >
                {gettext("Bib")}
              </th>
              <th
                :if={show_col?(@show_columns, "name")}
                class="sticky top-0 z-10 bg-base-100 px-6 py-4 font-semibold border-b-2 border-base-300/50 text-left"
              >
                {gettext("Name")}
              </th>
              <th
                :if={show_col?(@show_columns, "club")}
                class="sticky top-0 z-10 bg-base-100 px-6 py-4 font-semibold border-b-2 border-base-300/50 text-left"
              >
                {gettext("Club")}
              </th>
              <th
                :for={split <- @splits}
                :if={show_col?(@show_columns, "splits")}
                class="sticky top-0 z-10 bg-base-100 px-6 py-4 font-semibold border-b-2 border-base-300/50 text-right"
              >
                {split.short_name}
              </th>
              <th
                :if={show_col?(@show_columns, "total")}
                class="sticky top-0 z-10 bg-base-100 px-6 py-4 font-bold border-b-2 border-base-300/50 text-right"
              >
                {gettext("Total")}
              </th>
              <th
                :if={show_col?(@show_columns, "status")}
                class="sticky top-0 z-10 bg-base-100 w-32 px-6 py-4 font-semibold border-b-2 border-base-300/50 text-center"
              >
                {gettext("Status")}
              </th>
            </tr>
          </thead>
          <tbody id="kiosk-results">
            <tr
              :for={result <- @filtered_results}
              id={"kiosk-result-#{result.participant.id}"}
              class={[
                "kiosk-row even:bg-base-200/30",
                MapSet.member?(@recently_finished, result.participant.id) &&
                  "kiosk-flash"
              ]}
            >
              <td
                :if={show_col?(@show_columns, "rank")}
                class="text-center px-6 py-3 border-b border-base-300/20"
              >
                <.rank_badge :if={display_rank(result)} rank={display_rank(result)} size={:lg} />
                <span
                  :if={display_rank(result) == nil && result.status in [:dns, :dnf, :dsq]}
                  class="text-base-content/20 text-xl"
                >
                  &mdash;
                </span>
              </td>
              <td
                :if={show_col?(@show_columns, "bib")}
                class="font-mono text-xl px-6 py-3 border-b border-base-300/20 text-base-content/70"
              >
                {result.participant.bib_number}
              </td>
              <td
                :if={show_col?(@show_columns, "name")}
                class="text-xl font-medium px-6 py-3 border-b border-base-300/20 text-base-content"
              >
                {result.participant.first_name} {result.participant.last_name}
              </td>
              <td
                :if={show_col?(@show_columns, "club")}
                class="text-lg text-base-content/50 px-6 py-3 border-b border-base-300/20"
              >
                {result.participant.club || "\u2014"}
              </td>
              <%= if show_col?(@show_columns, "splits") do %>
                <%= if result.status in [:dns, :dnf, :dsq] do %>
                  <td
                    :for={_split <- @splits}
                    class="text-right font-mono text-xl px-6 py-3 border-b border-base-300/20 text-base-content/20"
                  >
                    &mdash;
                  </td>
                <% else %>
                  <td
                    :for={split <- @splits}
                    class="text-right font-mono text-xl px-6 py-3 border-b border-base-300/20 text-base-content/70"
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
                      class="text-sm text-base-content/40"
                    >
                      {pace_text}
                    </div>
                  </td>
                <% end %>
              <% end %>
              <td
                :if={show_col?(@show_columns, "total")}
                class="text-right font-mono text-2xl font-bold px-6 py-3 border-b border-base-300/20 text-base-content"
              >
                <%= if result.status in [:dns, :dnf, :dsq] do %>
                  <span class="text-base-content/20">&mdash;</span>
                <% else %>
                  {Calculator.format_time(result.total_ms)}
                <% end %>
              </td>
              <td
                :if={show_col?(@show_columns, "status")}
                class="text-center px-6 py-3 border-b border-base-300/20"
              >
                <span class={kiosk_status_class(result.status)}>
                  {format_participant_status(result.status)}
                </span>
              </td>
            </tr>
          </tbody>
        </table>

        <%!-- Empty state --%>
        <div :if={@filtered_results == []} class="flex items-center justify-center h-full">
          <div class="text-center">
            <.icon name="hero-clock" class="size-16 text-base-content/20 mx-auto mb-4" />
            <p class="text-2xl font-medium text-base-content/40">
              {gettext("Waiting for results...")}
            </p>
          </div>
        </div>
      </div>
    </div>

    <%!-- Colocated JS hook for auto-scrolling --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".KioskScroll">
      export default {
        mounted() {
          this.scrollArea = document.getElementById("kiosk-scroll-area");
          this.paused = false;
          this.speed = this.getSpeed();

          // Start auto-scroll
          this.startScroll();

          // Pause on mouse move, resume after idle
          this.idleTimer = null;
          document.addEventListener("mousemove", () => {
            this.paused = true;
            document.body.style.cursor = "default";
            clearTimeout(this.idleTimer);
            this.idleTimer = setTimeout(() => {
              this.paused = false;
              document.body.style.cursor = "none";
            }, 3000);
          });

          // Handle server push for new finisher flash
          this.handleEvent("flash-finisher", ({id}) => {
            const row = document.getElementById(`kiosk-result-${id}`);
            if (row) {
              row.classList.add("kiosk-flash");
              setTimeout(() => row.classList.remove("kiosk-flash"), 10000);
            }
          });
        },

        updated() {
          this.speed = this.getSpeed();
        },

        getSpeed() {
          const speedParam = this.el.dataset.scrollSpeed;
          switch (speedParam) {
            case "slow": return 0.3;
            case "fast": return 1.5;
            default: return 0.7;
          }
        },

        startScroll() {
          const scroll = () => {
            if (!this.paused && this.scrollArea) {
              const area = this.scrollArea;
              const maxScroll = area.scrollHeight - area.clientHeight;

              if (maxScroll > 0) {
                area.scrollTop += this.speed;

                // Loop back to top when reaching bottom (with a brief pause)
                if (area.scrollTop >= maxScroll) {
                  setTimeout(() => {
                    if (this.scrollArea) {
                      this.scrollArea.scrollTop = 0;
                    }
                  }, 2000);
                }
              }
            }
            this.animFrame = requestAnimationFrame(scroll);
          };
          this.animFrame = requestAnimationFrame(scroll);
        },

        destroyed() {
          if (this.animFrame) cancelAnimationFrame(this.animFrame);
          if (this.idleTimer) clearTimeout(this.idleTimer);
        }
      }
    </script>
    """
  end

  # --- Async data loading ---

  @impl true
  def handle_async(:load_kiosk_data, {:ok, data}, socket) do
    all_categories = build_category_list(socket.assigns)

    filtered =
      filter_by_index(data.results, all_categories, socket.assigns.current_category_index)

    {:noreply,
     assign(socket,
       results: data.results,
       splits: data.splits,
       loading: false,
       filtered_results: filtered
     )}
  end

  @impl true
  def handle_async(:load_kiosk_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  # --- PubSub handlers ---

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

    # Push flash events to client for each new finisher
    socket =
      Enum.reduce(newly_finished, socket, fn participant_id, sock ->
        Process.send_after(self(), {:clear_highlight, participant_id}, 10_000)
        push_event(sock, "flash-finisher", %{id: participant_id})
      end)

    recently_finished = MapSet.union(socket.assigns.recently_finished, newly_finished)

    {:noreply, assign(socket, recently_finished: recently_finished)}
  end

  @impl true
  def handle_info({:split_time_deleted, _split_time}, socket) do
    {:noreply, recalculate_results(socket)}
  end

  @impl true
  def handle_info({:clear_highlight, participant_id}, socket) do
    recently_finished = MapSet.delete(socket.assigns.recently_finished, participant_id)
    {:noreply, assign(socket, recently_finished: recently_finished)}
  end

  # --- Category rotation ---

  @impl true
  def handle_info(:rotate_category, socket) do
    all_categories = build_category_list(socket.assigns)
    next_index = rem(socket.assigns.current_category_index + 1, length(all_categories))
    {label, _filter} = Enum.at(all_categories, next_index)

    filtered = filter_by_index(socket.assigns.results, all_categories, next_index)

    timer = Process.send_after(self(), :rotate_category, @rotation_interval_ms)

    {:noreply,
     assign(socket,
       current_category_index: next_index,
       current_category_label: label,
       filtered_results: filtered,
       rotation_timer: timer
     )}
  end

  # --- Helpers ---

  defp recalculate_results(socket) do
    race = socket.assigns.race
    results = Results.get_race_results(race.id)

    all_categories = build_category_list(socket.assigns)
    filtered = filter_by_index(results, all_categories, socket.assigns.current_category_index)

    assign(socket, results: results, filtered_results: filtered)
  end

  defp build_category_list(assigns) do
    manual =
      Enum.map(assigns.categories, fn cat ->
        {cat.name, {:manual, cat.id}}
      end)

    auto =
      Enum.map(assigns.auto_categories, fn cat ->
        {cat.name, {:auto, cat.id}}
      end)

    [{gettext("Overall"), nil}] ++ manual ++ auto
  end

  defp filter_by_index(results, all_categories, index) do
    {_label, filter} = Enum.at(all_categories, index, {gettext("Overall"), nil})

    case filter do
      nil ->
        results

      {:manual, cat_id} ->
        results
        |> Enum.filter(fn r -> r.category != nil and r.category.id == cat_id end)
        |> Ranker.rank_results()

      {:auto, auto_cat_id} ->
        results
        |> Enum.filter(fn r ->
          Enum.any?(r.auto_categories, &(&1.id == auto_cat_id))
        end)
        |> Ranker.rank_results()
    end
  end

  defp match_category_param?({:manual, id}, param) do
    param == "manual:#{id}" || param == "#{id}"
  end

  defp match_category_param?({:auto, id}, param) do
    param == "auto:#{id}"
  end

  defp match_category_param?(nil, _param), do: false

  defp show_col?(columns, col), do: MapSet.member?(columns, col)

  defp display_rank(result) do
    if result.status == :finished, do: result.rank, else: nil
  end

  defp kiosk_status_class(:dns),
    do:
      "inline-flex items-center rounded-full bg-warning/15 text-warning px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(:dnf),
    do:
      "inline-flex items-center rounded-full bg-error/15 text-error px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(:dsq),
    do:
      "inline-flex items-center rounded-full bg-error/15 text-error px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(:finished),
    do:
      "inline-flex items-center rounded-full bg-success/15 text-success px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(:racing),
    do:
      "inline-flex items-center rounded-full bg-info/15 text-info px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(:registered),
    do:
      "inline-flex items-center rounded-full bg-base-content/10 text-base-content/60 px-3 py-1 text-base font-semibold"

  defp kiosk_status_class(_),
    do: "text-base-content/40"
end
