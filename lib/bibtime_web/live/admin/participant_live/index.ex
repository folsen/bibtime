defmodule BibtimeWeb.Admin.ParticipantLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants

  @page_size 25

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id)
    participants = Participants.list_participants(race_id)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:participants, participants)
     |> assign(:search, "")
     |> assign(:sort_by, "bib")
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> assign_filtered(participants, "bib", :asc)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    filtered =
      if search == "" do
        socket.assigns.participants
      else
        term = String.downcase(search)

        Enum.filter(socket.assigns.participants, fn p ->
          String.contains?(String.downcase(p.first_name || ""), term) or
            String.contains?(String.downcase(p.last_name || ""), term) or
            String.contains?(String.downcase(p.bib_number || ""), term)
        end)
      end

    filtered = sort_participants(filtered, socket.assigns.sort_by, socket.assigns.sort_dir)

    {:noreply,
     socket
     |> assign(search: search, page: 1)
     |> assign_paginated(filtered)}
  end

  @impl true
  def handle_event("sort", %{"col" => col}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col do
        {col, toggle_dir(socket.assigns.sort_dir)}
      else
        {col, :asc}
      end

    filtered = sort_participants(socket.assigns.all_filtered, sort_by, sort_dir)

    {:noreply,
     socket
     |> assign(sort_by: sort_by, sort_dir: sort_dir, page: 1)
     |> assign_paginated(filtered)}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, socket |> assign(:page, page) |> paginate(socket.assigns.all_filtered)}
  end

  @impl true
  def handle_event("mark_dns", %{"id" => id}, socket) do
    participant = Participants.get_participant!(id)
    {:ok, _} = Participants.mark_dns(participant)
    {:noreply, reload_participants(socket)}
  end

  @impl true
  def handle_event("mark_dnf", %{"id" => id}, socket) do
    participant = Participants.get_participant!(id)
    {:ok, _} = Participants.mark_dnf(participant)
    {:noreply, reload_participants(socket)}
  end

  @impl true
  def handle_event("mark_dsq", %{"id" => id}, socket) do
    participant = Participants.get_participant!(id)
    {:ok, _} = Participants.mark_dsq(participant)
    {:noreply, reload_participants(socket)}
  end

  defp assign_filtered(socket, participants, sort_by, sort_dir) do
    filtered = sort_participants(participants, sort_by, sort_dir)
    assign_paginated(socket, filtered)
  end

  defp assign_paginated(socket, all_filtered) do
    socket
    |> assign(:all_filtered, all_filtered)
    |> assign(:total_count, length(all_filtered))
    |> assign(:total_pages, max(1, ceil(length(all_filtered) / @page_size)))
    |> paginate(all_filtered)
  end

  defp paginate(socket, all_filtered) do
    page = socket.assigns.page
    page_items = all_filtered |> Enum.drop((page - 1) * @page_size) |> Enum.take(@page_size)
    assign(socket, :filtered_participants, page_items)
  end

  defp reload_participants(socket) do
    race_id = socket.assigns.race.id
    participants = Participants.list_participants(race_id)
    search = socket.assigns.search

    filtered =
      if search == "" do
        participants
      else
        term = String.downcase(search)

        Enum.filter(participants, fn p ->
          String.contains?(String.downcase(p.first_name || ""), term) or
            String.contains?(String.downcase(p.last_name || ""), term) or
            String.contains?(String.downcase(p.bib_number || ""), term)
        end)
      end

    filtered = sort_participants(filtered, socket.assigns.sort_by, socket.assigns.sort_dir)

    socket
    |> assign(:participants, participants)
    |> assign_paginated(filtered)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 pb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Participants")}
        </h1>
        <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
      </div>
      <.button navigate={~p"/admin/races/#{@race.id}/participants/new"} variant="primary">
        <.icon name="hero-plus" class="size-4 mr-1" /> {gettext("Add Participant")}
      </.button>
    </div>

    <%!-- Search --%>
    <div class="mb-5">
      <form phx-change="search" phx-submit="search">
        <div class="relative max-w-sm">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <.icon name="hero-magnifying-glass" class="size-4 text-base-content/40" />
          </div>
          <input
            type="text"
            name="search"
            value={@search}
            placeholder={gettext("Search by name or bib...")}
            class="input w-full pl-10 rounded-lg border-base-300 bg-base-100 focus:border-primary/50 focus:ring-primary/20"
            phx-debounce="300"
          />
        </div>
      </form>
    </div>

    <%!-- Pagination top --%>
    <.pagination
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <%!-- Table --%>
    <div
      :if={@filtered_participants != []}
      class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
    >
      <table class="table w-full">
        <thead>
          <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
            <th
              phx-click="sort"
              phx-value-col="bib"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Bib")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="bib" />
            </th>
            <th
              phx-click="sort"
              phx-value-col="name"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Name")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="name" />
            </th>
            <th
              phx-click="sort"
              phx-value-col="email"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Email")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="email" />
            </th>
            <th
              phx-click="sort"
              phx-value-col="category"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Category")}<.sort_indicator
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                col="category"
              />
            </th>
            <th
              phx-click="sort"
              phx-value-col="club"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Club")}<.sort_indicator sort_by={@sort_by} sort_dir={@sort_dir} col="club" />
            </th>
            <th
              phx-click="sort"
              phx-value-col="status"
              class="font-semibold cursor-pointer hover:text-base-content select-none"
            >
              {gettext("Status")}<.sort_indicator
                sort_by={@sort_by}
                sort_dir={@sort_dir}
                col="status"
              />
            </th>
            <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={participant <- @filtered_participants}
            id={"participant-#{participant.id}"}
            class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30 hover:bg-primary/5 transition-colors"
          >
            <td class="py-3">
              <span class="font-mono font-semibold text-primary">{participant.bib_number}</span>
            </td>
            <td class="py-3 font-medium">
              {participant.first_name} {participant.last_name}
            </td>
            <td class="py-3 text-sm text-base-content/70">{participant.email || "-"}</td>
            <td class="py-3 text-sm text-base-content/70">
              {if participant.race_category, do: participant.race_category.name, else: "-"}
            </td>
            <td class="py-3 text-sm text-base-content/70">{participant.club || "-"}</td>
            <td class="py-3">
              <span class={[
                "rounded-full px-2.5 py-0.5 text-xs font-medium",
                participant_status_pill(participant.status)
              ]}>
                {format_participant_status_upper(participant.status)}
              </span>
            </td>
            <td class="py-3">
              <div class="flex items-center gap-2">
                <.link
                  navigate={~p"/admin/races/#{@race.id}/participants/#{participant.id}/edit"}
                  class="text-sm font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  {gettext("Edit")}
                </.link>
                <button
                  phx-click="mark_dns"
                  phx-value-id={participant.id}
                  class="rounded-full border border-warning/30 bg-warning/10 px-2 py-0.5 text-xs font-medium text-warning hover:bg-warning/20 transition-colors"
                >
                  DNS
                </button>
                <button
                  phx-click="mark_dnf"
                  phx-value-id={participant.id}
                  class="rounded-full border border-warning/30 bg-warning/10 px-2 py-0.5 text-xs font-medium text-warning hover:bg-warning/20 transition-colors"
                >
                  DNF
                </button>
                <button
                  phx-click="mark_dsq"
                  phx-value-id={participant.id}
                  class="rounded-full border border-error/30 bg-error/10 px-2 py-0.5 text-xs font-medium text-error hover:bg-error/20 transition-colors"
                >
                  DSQ
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <%!-- Pagination bottom --%>
    <.pagination
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <div
      :if={@filtered_participants == [] and @all_filtered == []}
      class="flex flex-col items-center justify-center py-16 text-center"
    >
      <div class="rounded-full bg-base-200 p-4 mb-4">
        <.icon name="hero-users" class="size-10 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content/80 mb-1">
        {gettext("No participants found")}
      </h3>
      <p class="text-sm text-base-content/50 max-w-sm">
        {if @search != "",
          do: gettext("Try adjusting your search terms."),
          else: gettext("Add your first participant to get started.")}
      </p>
    </div>
    """
  end

  defp participant_status_pill(status) do
    case status do
      :registered -> "bg-base-content/10 text-base-content/60"
      :racing -> "bg-info/15 text-info"
      :dns -> "bg-warning/15 text-warning"
      :dnf -> "bg-warning/15 text-warning"
      :dsq -> "bg-error/15 text-error"
      :finished -> "bg-success/15 text-success"
      _ -> "bg-base-content/10 text-base-content/60"
    end
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_participants(participants, sort_by, sort_dir) do
    sorted =
      case sort_by do
        "bib" ->
          Enum.sort_by(participants, fn p ->
            case Integer.parse(p.bib_number || "") do
              {n, _} -> n
              :error -> 999_999
            end
          end)

        "name" ->
          Enum.sort_by(participants, fn p ->
            String.downcase("#{p.last_name} #{p.first_name}")
          end)

        "email" ->
          Enum.sort_by(participants, fn p ->
            String.downcase(p.email || "zzz")
          end)

        "category" ->
          Enum.sort_by(participants, fn p ->
            if p.race_category, do: String.downcase(p.race_category.name), else: "zzz"
          end)

        "club" ->
          Enum.sort_by(participants, fn p ->
            String.downcase(p.club || "zzz")
          end)

        "status" ->
          Enum.sort_by(participants, fn p -> Atom.to_string(p.status) end)

        _ ->
          participants
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
