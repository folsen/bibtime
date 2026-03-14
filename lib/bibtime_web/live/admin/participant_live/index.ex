defmodule BibtimeWeb.Admin.ParticipantLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id)
    participants = Participants.list_participants(race_id)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:participants, participants)
     |> assign(:search, "")
     |> assign(:filtered_participants, participants)}
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

    {:noreply, assign(socket, search: search, filtered_participants: filtered)}
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

    assign(socket, participants: participants, filtered_participants: filtered)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 pb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">Participants</h1>
        <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
      </div>
      <.button navigate={~p"/admin/races/#{@race.id}/participants/new"} variant="primary">
        <.icon name="hero-plus" class="size-4 mr-1" /> Add Participant
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
            placeholder="Search by name or bib..."
            class="input w-full pl-10 rounded-lg border-base-300 bg-base-100 focus:border-primary/50 focus:ring-primary/20"
            phx-debounce="300"
          />
        </div>
      </form>
    </div>

    <%!-- Table --%>
    <div :if={@filtered_participants != []} class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm">
      <table class="table w-full">
        <thead>
          <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
            <th class="font-semibold">Bib</th>
            <th class="font-semibold">Name</th>
            <th class="font-semibold">Email</th>
            <th class="font-semibold">Category</th>
            <th class="font-semibold">Club</th>
            <th class="font-semibold">Status</th>
            <th class="font-semibold"><span class="sr-only">Actions</span></th>
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
              <span class={["rounded-full px-2.5 py-0.5 text-xs font-medium", participant_status_pill(participant.status)]}>
                {format_status(participant.status)}
              </span>
            </td>
            <td class="py-3">
              <div class="flex items-center gap-2">
                <.link
                  navigate={~p"/admin/races/#{@race.id}/participants/#{participant.id}/edit"}
                  class="text-sm font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  Edit
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

    <div :if={@filtered_participants == []} class="flex flex-col items-center justify-center py-16 text-center">
      <div class="rounded-full bg-base-200 p-4 mb-4">
        <.icon name="hero-users" class="size-10 text-base-content/30" />
      </div>
      <h3 class="text-lg font-semibold text-base-content/80 mb-1">No participants found</h3>
      <p class="text-sm text-base-content/50 max-w-sm">
        {if @search != "", do: "Try adjusting your search terms.", else: "Add your first participant to get started."}
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

  defp format_status(status) do
    status
    |> Atom.to_string()
    |> String.upcase()
  end
end
