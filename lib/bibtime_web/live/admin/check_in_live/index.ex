defmodule BibtimeWeb.Admin.CheckInLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:checkin:#{race.id}")
    end

    socket =
      socket
      |> assign(:race, race)
      |> assign(:participants, [])
      |> assign(:search, "")
      |> assign(:selected_participant, nil)
      |> assign(:tag_input, "")
      |> assign(:last_scanned_tag, nil)
      |> assign(:last_scanned_at, nil)
      |> assign(:last_checked_in, nil)
      |> assign(:loading, true)
      |> assign(:error, nil)
      |> assign(:checked_in_count, 0)
      |> assign(:total_count, 0)

    socket =
      if connected?(socket) do
        start_async(socket, :load_participants, fn ->
          # Only registered-and-beyond participants have bibs and can be
          # checked in. Pending-payment holds are excluded.
          participants =
            race_id
            |> Participants.list_participants()
            |> Enum.reject(&is_nil(&1.bib_number))

          checked_in_count = Participants.count_checked_in_participants(race_id)
          %{participants: participants, checked_in_count: checked_in_count}
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_participants, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:participants, data.participants)
     |> assign(:checked_in_count, data.checked_in_count)
     |> assign(:total_count, length(data.participants))
     |> assign(:loading, false)}
  end

  @impl true
  def handle_async(:load_participants, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto">
      <%!-- Header --%>
      <div class="flex items-center justify-between gap-4 pb-4">
        <div>
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">
              {gettext("Check-In")}
            </h1>
            <.status_pill status={@race.status} />
          </div>
          <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
        </div>
        <div class="text-right">
          <div class="text-2xl font-bold font-mono text-primary">
            {@checked_in_count} / {@total_count}
          </div>
          <p class="text-xs text-base-content/50 uppercase tracking-wider">
            {gettext("checked in")}
          </p>
        </div>
      </div>

      <%!-- Success banner --%>
      <div
        :if={@last_checked_in}
        class="rounded-xl border border-success/30 bg-success/5 p-4 mb-4 flex items-center gap-4"
      >
        <div class="rounded-full bg-success/15 p-2">
          <.icon name="hero-check-circle" class="size-6 text-success" />
        </div>
        <div>
          <p class="text-xs font-semibold text-success uppercase tracking-wider mb-0.5">
            {gettext("Checked in")}
          </p>
          <p class="text-base text-base-content">
            <span class="font-mono font-bold text-primary">
              #{@last_checked_in.bib_number}
            </span>
            <span class="mx-1.5 text-base-content/30">|</span>
            {@last_checked_in.first_name} {@last_checked_in.last_name}
            <span class="mx-1.5 text-base-content/30">|</span>
            <span class="font-mono text-base-content/70">{@last_checked_in.chip_id}</span>
          </p>
        </div>
      </div>

      <%!-- Error banner --%>
      <div
        :if={@error}
        class="mb-4 flex items-center gap-2 rounded-lg bg-warning/10 border border-warning/30 px-4 py-2.5 text-sm text-warning"
      >
        <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
        <span>{@error}</span>
      </div>

      <%!-- Two-column layout --%>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <%!-- Left: Participant list (2/3 width) --%>
        <div class="lg:col-span-2">
          <%!-- Search --%>
          <div class="mb-4">
            <form phx-change="search" phx-submit="search">
              <div class="relative">
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

          <%!-- Loading skeleton --%>
          <div :if={@loading} class="rounded-xl border border-base-300 bg-base-100 shadow-sm p-6">
            <div class="animate-pulse space-y-4">
              <div class="h-8 bg-base-200 rounded-lg w-full"></div>
              <div class="h-6 bg-base-200/60 rounded w-11/12"></div>
              <div class="h-6 bg-base-200/60 rounded w-full"></div>
              <div class="h-6 bg-base-200/60 rounded w-10/12"></div>
              <div class="h-6 bg-base-200/60 rounded w-full"></div>
            </div>
          </div>

          <%!-- Participant table --%>
          <div
            :if={!@loading and filtered_participants(@participants, @search) != []}
            class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
          >
            <table class="table w-full">
              <thead>
                <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
                  <th class="font-semibold">{gettext("Bib")}</th>
                  <th class="font-semibold">{gettext("Name")}</th>
                  <th class="font-semibold hidden sm:table-cell">{gettext("Tag")}</th>
                  <th class="font-semibold">{gettext("Status")}</th>
                  <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={p <- filtered_participants(@participants, @search)}
                  id={"participant-#{p.id}"}
                  phx-click="select_participant"
                  phx-value-id={p.id}
                  class={[
                    "border-b border-base-200 cursor-pointer transition-colors",
                    cond do
                      @selected_participant && @selected_participant.id == p.id ->
                        "bg-primary/10 border-primary/30"

                      p.status == :checked_in ->
                        "bg-success/5 hover:bg-success/10"

                      true ->
                        "odd:bg-base-100 even:bg-base-200/30 hover:bg-primary/5"
                    end
                  ]}
                >
                  <td class="py-3">
                    <span class="font-mono font-bold text-primary">{p.bib_number}</span>
                  </td>
                  <td class="py-3 font-medium">
                    {p.first_name} {p.last_name}
                  </td>
                  <td class="py-3 text-sm text-base-content/70 hidden sm:table-cell">
                    <span :if={p.chip_id} class="font-mono text-xs">{p.chip_id}</span>
                    <span :if={!p.chip_id} class="text-base-content/30">--</span>
                  </td>
                  <td class="py-3">
                    <span :if={p.status == :checked_in} class="inline-flex items-center gap-1">
                      <.icon name="hero-check-circle-solid" class="size-4 text-success" />
                      <span class="text-xs font-medium text-success">
                        {gettext("Checked In")}
                      </span>
                    </span>
                    <span
                      :if={p.status != :checked_in}
                      class="text-xs text-base-content/40"
                    >
                      {format_participant_status(p.status)}
                    </span>
                  </td>
                  <td class="py-3">
                    <button
                      :if={p.chip_id}
                      phx-click="unassign_tag"
                      phx-value-id={p.id}
                      class="text-xs font-medium text-error/70 hover:text-error transition-colors"
                      data-confirm={gettext("Remove tag assignment?")}
                    >
                      {gettext("Unassign")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <%!-- Empty state --%>
          <div
            :if={!@loading and filtered_participants(@participants, @search) == []}
            class="flex flex-col items-center py-12 text-center"
          >
            <.icon name="hero-users" class="size-8 text-base-content/20 mb-2" />
            <p class="text-sm text-base-content/50">
              {if @search != "",
                do: gettext("No participants match your search."),
                else: gettext("No participants registered yet.")}
            </p>
          </div>
        </div>

        <%!-- Right: Scan panel (1/3 width) --%>
        <div class="lg:col-span-1">
          <div class="sticky top-6">
            <%!-- No participant selected --%>
            <div
              :if={!@selected_participant}
              class="rounded-xl border border-base-300 bg-base-100 shadow-sm p-6 text-center"
            >
              <div class="rounded-full bg-base-200 p-4 inline-block mb-3">
                <.icon name="hero-identification" class="size-8 text-base-content/30" />
              </div>
              <h3 class="text-sm font-semibold text-base-content/60 mb-1">
                {gettext("Select a participant")}
              </h3>
              <p class="text-xs text-base-content/40">
                {gettext("Click a participant from the list, then scan their RFID tag.")}
              </p>

              <%!-- Allow scanning without selection for lookup --%>
              <div class="mt-6 pt-4 border-t border-base-200">
                <p class="text-xs text-base-content/40 mb-2">
                  {gettext("Or scan a tag to look up its owner")}
                </p>
                <form phx-submit="scan_tag">
                  <input
                    type="text"
                    name="tag"
                    value={@tag_input}
                    phx-change="update_tag"
                    placeholder={gettext("Scan tag...")}
                    class="input input-sm w-full font-mono text-sm border-base-300 bg-base-100 focus:border-primary/50 focus:ring-primary/20"
                    autocomplete="off"
                  />
                </form>
              </div>
            </div>

            <%!-- Participant selected --%>
            <div
              :if={@selected_participant}
              class="rounded-xl border border-primary/30 bg-primary/5 shadow-sm overflow-hidden"
            >
              <div class="p-5">
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-xs font-semibold text-primary uppercase tracking-wider">
                    {gettext("Selected Participant")}
                  </h3>
                  <button
                    phx-click="deselect_participant"
                    class="text-xs text-base-content/40 hover:text-base-content transition-colors"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>

                <div class="mb-4">
                  <div class="text-3xl font-mono font-bold text-primary mb-1">
                    #{@selected_participant.bib_number}
                  </div>
                  <div class="text-lg font-medium text-base-content">
                    {@selected_participant.first_name} {@selected_participant.last_name}
                  </div>
                  <div :if={@selected_participant.club} class="text-sm text-base-content/50 mt-0.5">
                    {@selected_participant.club}
                  </div>
                </div>

                <div
                  :if={@selected_participant.chip_id}
                  class="rounded-lg bg-base-100 border border-base-300 px-3 py-2 mb-4"
                >
                  <span class="text-xs text-base-content/50">{gettext("Current tag:")}</span>
                  <span class="font-mono text-sm ml-1">{@selected_participant.chip_id}</span>
                </div>

                <%!-- Tag scan form --%>
                <div>
                  <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 block">
                    {gettext("Scan RFID Tag")}
                  </label>
                  <form phx-submit="scan_tag" class="flex gap-2">
                    <input
                      type="text"
                      name="tag"
                      id="tag-input"
                      value={@tag_input}
                      phx-change="update_tag"
                      phx-hook=".AutoFocusTag"
                      placeholder={gettext("Scan tag...")}
                      class="input input-lg flex-1 font-mono text-lg tracking-wider border-base-300 bg-base-100 focus:border-primary/50 focus:ring-primary/20"
                      autocomplete="off"
                    />
                    <button
                      type="submit"
                      class="btn btn-lg bg-primary text-primary-content hover:bg-primary/90 border-none shadow-md font-bold min-h-[44px]"
                    >
                      <.icon name="hero-check" class="size-5" />
                    </button>
                  </form>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <%!-- Colocated JS hook for auto-focusing the tag input --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoFocusTag">
      export default {
        mounted() {
          this.el.focus();
        },
        updated() {
          this.el.focus();
        }
      }
    </script>
    """
  end

  # --------------------------------------------------------------------------
  # Events
  # --------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, assign(socket, :search, search)}
  end

  def handle_event("select_participant", %{"id" => id}, socket) do
    id = String.to_integer(id)
    participant = Enum.find(socket.assigns.participants, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_participant, participant)
     |> assign(:tag_input, "")
     |> assign(:error, nil)}
  end

  def handle_event("deselect_participant", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_participant, nil)
     |> assign(:tag_input, "")
     |> assign(:error, nil)}
  end

  def handle_event("update_tag", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :tag_input, tag)}
  end

  def handle_event("scan_tag", %{"tag" => tag}, socket) do
    tag = String.trim(tag)
    now = DateTime.utc_now()

    cond do
      tag == "" ->
        {:noreply, assign(socket, :error, gettext("No tag scanned."))}

      duplicate_scan?(tag, socket.assigns.last_scanned_tag, socket.assigns.last_scanned_at, now) ->
        {:noreply,
         socket
         |> assign(:tag_input, "")
         |> assign(:last_scanned_tag, tag)
         |> assign(:last_scanned_at, now)}

      is_nil(socket.assigns.selected_participant) ->
        handle_lookup_scan(tag, now, socket)

      true ->
        handle_assign_scan(tag, now, socket)
    end
  end

  def handle_event("unassign_tag", %{"id" => id}, socket) do
    id = String.to_integer(id)
    participant = Enum.find(socket.assigns.participants, &(&1.id == id))

    case Participants.uncheck_in_participant(participant) do
      {:ok, updated} ->
        participants = update_participant_in_list(socket.assigns.participants, updated)

        {:noreply,
         socket
         |> assign(:participants, participants)
         |> assign(:checked_in_count, socket.assigns.checked_in_count - 1)
         |> assign(:selected_participant, nil)
         |> assign(:error, nil)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, gettext("Failed to unassign tag."))}
    end
  end

  # --------------------------------------------------------------------------
  # PubSub
  # --------------------------------------------------------------------------

  @impl true
  def handle_info({:participant_checked_in, updated}, socket) do
    participants = update_participant_in_list(socket.assigns.participants, updated)
    checked_in_count = Enum.count(participants, &(!is_nil(&1.checked_in_at)))

    {:noreply,
     socket
     |> assign(:participants, participants)
     |> assign(:checked_in_count, checked_in_count)}
  end

  def handle_info({:participant_unchecked, updated}, socket) do
    participants = update_participant_in_list(socket.assigns.participants, updated)
    checked_in_count = Enum.count(participants, &(!is_nil(&1.checked_in_at)))

    {:noreply,
     socket
     |> assign(:participants, participants)
     |> assign(:checked_in_count, checked_in_count)}
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp duplicate_scan?(_tag, _last_tag, nil, _now), do: false

  defp duplicate_scan?(tag, last_tag, last_at, now) do
    tag == last_tag and DateTime.diff(now, last_at, :millisecond) < 2_000
  end

  defp handle_lookup_scan(tag, now, socket) do
    race_id = socket.assigns.race.id

    case Participants.get_participant_by_chip(race_id, tag) do
      nil ->
        {:noreply,
         socket
         |> assign(:error, gettext("Tag not assigned to any participant. Select one first."))
         |> assign(:tag_input, "")
         |> assign(:last_scanned_tag, tag)
         |> assign(:last_scanned_at, now)}

      participant ->
        {:noreply,
         socket
         |> assign(:selected_participant, participant)
         |> assign(:tag_input, "")
         |> assign(:error, nil)
         |> assign(:last_scanned_tag, tag)
         |> assign(:last_scanned_at, now)}
    end
  end

  defp handle_assign_scan(tag, now, socket) do
    race_id = socket.assigns.race.id
    selected = socket.assigns.selected_participant

    case Participants.get_participant_by_chip(race_id, tag) do
      %{id: id} = existing when id != selected.id ->
        {:noreply,
         socket
         |> assign(
           :error,
           gettext("Tag already assigned to #%{bib} %{name}.",
             bib: existing.bib_number,
             name: "#{existing.first_name} #{existing.last_name}"
           )
         )
         |> assign(:tag_input, "")
         |> assign(:last_scanned_tag, tag)
         |> assign(:last_scanned_at, now)}

      _ ->
        case Participants.check_in_participant(selected, tag) do
          {:ok, updated} ->
            participants = update_participant_in_list(socket.assigns.participants, updated)

            {:noreply,
             socket
             |> assign(:participants, participants)
             |> assign(:checked_in_count, socket.assigns.checked_in_count + 1)
             |> assign(:last_checked_in, updated)
             |> assign(:selected_participant, nil)
             |> assign(:tag_input, "")
             |> assign(:error, nil)
             |> assign(:last_scanned_tag, tag)
             |> assign(:last_scanned_at, now)}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:error, gettext("Failed to assign tag."))
             |> assign(:tag_input, "")
             |> assign(:last_scanned_tag, tag)
             |> assign(:last_scanned_at, now)}
        end
    end
  end

  defp filtered_participants(participants, "") do
    participants
  end

  defp filtered_participants(participants, search) do
    term = String.downcase(search)

    Enum.filter(participants, fn p ->
      String.contains?(String.downcase(p.first_name || ""), term) or
        String.contains?(String.downcase(p.last_name || ""), term) or
        String.contains?(String.downcase(p.bib_number || ""), term)
    end)
  end

  defp update_participant_in_list(participants, updated) do
    Enum.map(participants, fn p ->
      if p.id == updated.id, do: updated, else: p
    end)
  end
end
