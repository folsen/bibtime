defmodule BibtimeWeb.Admin.ParticipantLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Participants.CSVImport
  alias Bibtime.AuditLog

  @page_size 25

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id, preload: [:categories])

    socket =
      socket
      |> assign(:race, race)
      |> assign(:participants, [])
      |> assign(:search, "")
      |> assign(:sort_by, "bib")
      |> assign(:sort_dir, :asc)
      |> assign(:page, 1)
      |> assign(:page_size, @page_size)
      |> assign(:loading, true)
      |> assign(:all_filtered, [])
      |> assign(:total_count, 0)
      |> assign(:total_pages, 1)
      |> assign(:filtered_participants, [])
      |> assign(:show_import, false)
      |> assign(:import_errors, [])
      |> allow_upload(:csv,
        accept: ~w(.csv text/csv),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    socket =
      if connected?(socket) do
        start_async(socket, :load_participants, fn ->
          Participants.list_participants(race_id)
        end)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:load_participants, {:ok, participants}, socket) do
    {:noreply,
     socket
     |> assign(:participants, participants)
     |> assign(:loading, false)
     |> assign_filtered(participants, socket.assigns.sort_by, socket.assigns.sort_dir)}
  end

  @impl true
  def handle_async(:load_participants, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
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
  def handle_event("toggle_import", _params, socket) do
    {:noreply, assign(socket, show_import: !socket.assigns.show_import, import_errors: [])}
  end

  @impl true
  def handle_event("validate_import", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_import_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv, ref)}
  end

  @impl true
  def handle_event("run_import", _params, socket) do
    race_id = socket.assigns.race.id

    result =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        case File.read(path) do
          {:ok, contents} -> {:ok, CSVImport.import(contents, race_id)}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    case result do
      [{:ok, %{imported: count}}] ->
        AuditLog.log(
          socket.assigns.current_scope.user,
          "participants.imported",
          "race",
          race_id,
          %{"count" => count}
        )

        {:noreply,
         socket
         |> assign(show_import: false, import_errors: [])
         |> put_flash(
           :info,
           ngettext(
             "Imported %{count} participant.",
             "Imported %{count} participants.",
             count
           )
         )
         |> reload_participants()}

      [{:error, errors}] ->
        {:noreply, assign(socket, import_errors: errors)}

      [] ->
        {:noreply,
         put_flash(socket, :error, gettext("No file selected. Please choose a CSV file."))}
    end
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
    stream(socket, :filtered_participants, page_items, reset: true)
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
      <div class="flex gap-2">
        <.button phx-click="toggle_import">
          <.icon name="hero-arrow-up-tray" class="size-4 mr-1" /> {gettext("Import CSV")}
        </.button>
        <.button navigate={~p"/admin/races/#{@race.id}/participants/new"} variant="primary">
          <.icon name="hero-plus" class="size-4 mr-1" /> {gettext("Add Participant")}
        </.button>
      </div>
    </div>

    <%!-- Import panel --%>
    <div
      :if={@show_import}
      class="mb-5 rounded-xl border border-base-300 bg-base-100 shadow-sm p-5"
    >
      <div class="flex items-start justify-between mb-3">
        <div>
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Import participants from CSV")}
          </h2>
          <p class="text-sm text-base-content/60 mt-1">
            {gettext(
              "Columns: bib number, name, email (optional), category (optional), club (optional). A header row is optional."
            )}
          </p>
        </div>
        <button
          type="button"
          phx-click="toggle_import"
          class="btn btn-ghost btn-sm btn-circle"
          aria-label={gettext("Close")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <form id="csv-import-form" phx-submit="run_import" phx-change="validate_import">
        <div
          phx-drop-target={@uploads.csv.ref}
          class={[
            "border-2 border-dashed rounded-lg p-6 text-center transition-colors",
            if(@uploads.csv.entries != [],
              do: "border-primary/50 bg-primary/5",
              else: "border-base-300 hover:border-primary/40"
            )
          ]}
        >
          <.icon name="hero-document-text" class="size-10 mx-auto text-base-content/25 mb-2" />
          <p class="text-sm text-base-content/60 mb-2">
            {gettext("Drag a CSV file here or click to browse")}
          </p>
          <label for={@uploads.csv.ref} class="btn btn-sm cursor-pointer">
            {gettext("Choose File")}
          </label>
          <.live_file_input upload={@uploads.csv} class="sr-only" />
        </div>

        <div :if={@uploads.csv.entries != []} class="mt-3 space-y-2">
          <div
            :for={entry <- @uploads.csv.entries}
            class="flex items-center justify-between rounded border border-base-300 px-3 py-2"
          >
            <div class="flex items-center gap-2 text-sm">
              <.icon name="hero-document-text" class="size-4 text-base-content/50" />
              <span>{entry.client_name}</span>
            </div>
            <button
              type="button"
              phx-click="cancel_import_upload"
              phx-value-ref={entry.ref}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
            <p :for={err <- upload_errors(@uploads.csv, entry)} class="text-xs text-error">
              {upload_error_message(err)}
            </p>
          </div>
        </div>

        <div class="mt-4 flex gap-2">
          <.button
            type="submit"
            variant="primary"
            disabled={@uploads.csv.entries == []}
          >
            {gettext("Import")}
          </.button>
          <.button type="button" phx-click="toggle_import">
            {gettext("Cancel")}
          </.button>
        </div>
      </form>

      <div :if={@import_errors != []} class="mt-4 rounded-lg border border-error/30 bg-error/5 p-3">
        <p class="text-sm font-semibold text-error mb-2">
          {gettext("Import failed. Fix the errors and try again:")}
        </p>
        <ul class="text-sm text-error/90 space-y-1 list-disc list-inside">
          <li :for={err <- @import_errors}>
            {gettext("Row")} {err.row}, {err.field}: {err.message}
          </li>
        </ul>
      </div>
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

    <%!-- Loading skeleton --%>
    <div :if={@loading} class="rounded-xl border border-base-300 bg-base-100 shadow-sm p-6">
      <div class="animate-pulse space-y-4">
        <div class="h-8 bg-base-200 rounded-lg w-full"></div>
        <div class="h-6 bg-base-200/60 rounded w-11/12"></div>
        <div class="h-6 bg-base-200/60 rounded w-full"></div>
        <div class="h-6 bg-base-200/60 rounded w-10/12"></div>
        <div class="h-6 bg-base-200/60 rounded w-full"></div>
        <div class="h-6 bg-base-200/60 rounded w-9/12"></div>
      </div>
    </div>

    <%!-- Pagination top --%>
    <.pagination
      :if={!@loading}
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <%!-- Table --%>
    <div
      :if={!@loading and @total_count > 0}
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
              :if={@race.categories != []}
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
        <tbody id="participants" phx-update="stream">
          <tr
            :for={{dom_id, participant} <- @streams.filtered_participants}
            id={dom_id}
            class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30 hover:bg-primary/5 transition-colors"
          >
            <td class="py-3">
              <span
                :if={participant.bib_number}
                class="font-mono font-semibold text-primary"
              >
                {participant.bib_number}
              </span>
              <span
                :if={is_nil(participant.bib_number)}
                class="font-mono text-xs text-base-content/40"
              >
                —
              </span>
            </td>
            <td class="py-3 font-medium">
              {participant.first_name} {participant.last_name}
            </td>
            <td class="py-3 text-sm text-base-content/70">{participant_email(participant) || "-"}</td>
            <td :if={@race.categories != []} class="py-3 text-sm text-base-content/70">
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
      :if={!@loading}
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <div
      :if={!@loading and @total_count == 0}
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
      :checked_in -> "bg-success/15 text-success"
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
            String.downcase(participant_email(p) || "zzz")
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

  defp participant_email(%{user: %{email: email}}) when is_binary(email), do: email
  defp participant_email(_), do: nil

  defp upload_error_message(:too_large), do: gettext("File is too large (max 5MB)")
  defp upload_error_message(:too_many_files), do: gettext("Only one file allowed")
  defp upload_error_message(:not_accepted), do: gettext("Must be a .csv file")
  defp upload_error_message(_), do: gettext("Upload error")

  defp sort_indicator(assigns) do
    ~H"""
    <span :if={@sort_by == @col} class="ml-1 text-primary">
      <.icon :if={@sort_dir == :asc} name="hero-chevron-up-mini" class="size-3 inline" />
      <.icon :if={@sort_dir == :desc} name="hero-chevron-down-mini" class="size-3 inline" />
    </span>
    """
  end
end
