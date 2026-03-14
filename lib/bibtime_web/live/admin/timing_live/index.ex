defmodule BibtimeWeb.Admin.TimingLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Timing
  alias Bibtime.Timing.CSVImport
  alias Bibtime.Participants

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    race_start = Timing.get_race_start(race.id)
    splits = race.splits |> Enum.sort_by(& &1.sort_order)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")
    end

    recent_entries = load_recent_entries(race.id)

    socket =
      socket
      |> assign(:race, race)
      |> assign(:race_start, race_start)
      |> assign(:splits, splits)
      |> assign(:selected_split, List.first(splits))
      |> assign(:bib_input, "")
      |> assign(:recent_entries, recent_entries)
      |> assign(:next_up, load_next_up(race.id))
      |> assign(:error, nil)
      |> assign(:elapsed_seconds, compute_elapsed_seconds(race_start))
      |> assign(:csv_text, "")
      |> assign(:import_result, nil)
      |> assign(:import_errors, [])

    socket =
      if race_start && connected?(socket) do
        {:ok, timer_ref} = :timer.send_interval(1_000, self(), :tick)
        assign(socket, :timer_ref, timer_ref)
      else
        assign(socket, :timer_ref, nil)
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header --%>
      <div class="flex items-center justify-between gap-4 pb-6">
        <div>
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-semibold tracking-tight text-base-content">Timing Console</h1>
            <span class={["rounded-full px-2.5 py-0.5 text-xs font-medium", status_pill_class(@race.status)]}>
              {format_status(@race.status)}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
        </div>
      </div>

      <%!-- Start Race Section --%>
      <div :if={is_nil(@race_start)} class="flex flex-col items-center justify-center py-16 text-center">
        <div class="rounded-full bg-primary/10 p-5 mb-5">
          <.icon name="hero-play" class="size-12 text-primary/50" />
        </div>
        <h3 class="text-lg font-semibold text-base-content/80 mb-2">Race has not been started</h3>
        <p class="text-sm text-base-content/50 mb-6 max-w-sm">
          Once started, the clock will begin and you can record split times for participants.
        </p>
        <.button phx-click="start_race" variant="primary" class="btn btn-primary btn-lg">
          <.icon name="hero-play" class="size-5 mr-1" /> Start Race
        </.button>
      </div>

      <%!-- Race Started Section --%>
      <div :if={@race_start}>
        <%!-- Running Clock Card --%>
        <div class="rounded-2xl border border-primary/20 bg-primary/5 p-8 text-center mb-6 shadow-sm">
          <div class="text-7xl font-mono font-bold tracking-widest text-primary">
            {format_elapsed(@elapsed_seconds)}
          </div>
          <p class="mt-2 text-sm text-primary/60 font-medium uppercase tracking-wider">
            Elapsed since gun start
          </p>
        </div>

        <%!-- Split Selector --%>
        <div :if={@splits != []} class="mb-6">
          <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 block">
            Active Split
          </label>
          <div class="flex flex-wrap gap-2">
            <button
              :for={split <- @splits}
              phx-click="select_split"
              phx-value-split-id={split.id}
              class={[
                "rounded-full px-4 py-1.5 text-sm font-medium border transition-all",
                if(@selected_split && @selected_split.id == split.id,
                  do: "bg-primary text-primary-content border-primary shadow-sm",
                  else: "bg-base-100 text-base-content/60 border-base-300 hover:border-primary/40 hover:text-primary"
                )
              ]}
            >
              {split.name}
            </button>
          </div>
        </div>

        <%!-- Bib Entry Form --%>
        <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm mb-6">
          <label class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2 block">
            Bib Number
          </label>
          <form phx-submit="record_time" class="flex items-center gap-3">
            <div class="flex-1">
              <input
                name="bib"
                value={@bib_input}
                placeholder="Enter bib number..."
                phx-change="update_bib"
                class="input input-lg w-full font-mono text-2xl tracking-wider border-base-300 bg-base-100 focus:border-primary/50 focus:ring-primary/20"
                autocomplete="off"
              />
            </div>
            <button
              type="submit"
              class="btn btn-lg bg-primary text-primary-content hover:bg-primary/90 border-none shadow-md font-bold text-base tracking-wide px-8"
            >
              <.icon name="hero-clock" class="size-5 mr-1" /> Record
            </button>
          </form>

          <div
            :if={@error}
            class="mt-3 flex items-center gap-2 rounded-lg bg-warning/10 border border-warning/30 px-4 py-2.5 text-sm text-warning"
          >
            <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
            <span>{@error}</span>
          </div>
        </div>

        <%!-- Last Recording Confirmation --%>
        <div
          :if={@recent_entries != [] && hd(@recent_entries).participant}
          class="rounded-xl border border-success/30 bg-success/5 p-4 mb-6 flex items-center gap-4"
        >
          <div class="rounded-full bg-success/15 p-2">
            <.icon name="hero-check-circle" class="size-6 text-success" />
          </div>
          <div>
            <% entry = hd(@recent_entries) %>
            <p class="text-xs font-semibold text-success uppercase tracking-wider mb-0.5">Last recorded</p>
            <p class="text-base text-base-content">
              <span class="font-mono font-bold text-primary">#{entry.participant.bib_number}</span>
              <span class="mx-1.5 text-base-content/30">|</span>
              {entry.participant.first_name} {entry.participant.last_name}
              <span class="mx-1.5 text-base-content/30">|</span>
              <span class="font-medium">{entry.split.name}</span>
              <span class="mx-1.5 text-base-content/30">|</span>
              <span class="font-mono text-base-content/70">{format_elapsed_ms(entry.elapsed_ms)}</span>
            </p>
          </div>
        </div>

        <%!-- Next Up --%>
        <div :if={@next_up != []} class="mb-6">
          <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-2">Next Up</h3>
          <div class="flex flex-wrap gap-2">
            <button
              :for={p <- @next_up}
              phx-click="quick_bib"
              phx-value-bib={p.bib_number}
              class="inline-flex items-center gap-1.5 rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-sm hover:border-primary/40 hover:bg-primary/5 transition-colors"
            >
              <span class="font-mono font-bold text-primary">{p.bib_number}</span>
              <span class="text-base-content/60">{p.first_name} {p.last_name}</span>
              <span class="text-xs text-base-content/30 font-mono">{p.splits_completed}/{length(@splits)}</span>
            </button>
          </div>
        </div>

        <%!-- Recent Entries Table --%>
        <div class="mb-8">
          <h3 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">Recent Entries</h3>
          <div :if={@recent_entries != []} class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm">
            <table class="table w-full">
              <thead>
                <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
                  <th class="font-semibold">Bib</th>
                  <th class="font-semibold">Name</th>
                  <th class="font-semibold">Split</th>
                  <th class="font-semibold">Elapsed</th>
                  <th class="font-semibold"><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={entry <- @recent_entries}
                  id={"entry-#{entry.id}"}
                  class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
                >
                  <td class="py-3">
                    <span class="font-mono font-bold text-primary">{entry.participant.bib_number}</span>
                  </td>
                  <td class="py-3 text-sm">
                    {entry.participant.first_name} {entry.participant.last_name}
                  </td>
                  <td class="py-3 text-sm text-base-content/70">
                    {entry.split.name}
                  </td>
                  <td class="py-3">
                    <span class="font-mono text-sm">{format_elapsed_ms(entry.elapsed_ms)}</span>
                  </td>
                  <td class="py-3">
                    <button
                      phx-click="delete_entry"
                      phx-value-id={entry.id}
                      data-confirm="Delete this timing entry?"
                      class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                    >
                      Undo
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@recent_entries == []} class="flex flex-col items-center py-8 text-center">
            <.icon name="hero-clock" class="size-8 text-base-content/20 mb-2" />
            <p class="text-sm text-base-content/50">
              No recordings yet. Enter a bib number above to start recording times.
            </p>
          </div>
        </div>
      </div>

      <%!-- CSV Import Section --%>
      <details class="group mt-4 rounded-xl border border-base-300 bg-base-100 shadow-sm">
        <summary class="flex cursor-pointer items-center justify-between p-5 text-base-content/80 hover:text-base-content transition-colors">
          <div class="flex items-center gap-3">
            <div class="rounded-lg bg-base-200 p-2">
              <.icon name="hero-arrow-up-tray" class="size-5 text-base-content/50" />
            </div>
            <div>
              <h3 class="font-semibold text-sm">CSV Import</h3>
              <p class="text-xs text-base-content/50">Bulk import timing data from CSV</p>
            </div>
          </div>
          <.icon name="hero-chevron-down" class="size-5 text-base-content/40 transition-transform group-open:rotate-180" />
        </summary>

        <div class="border-t border-base-200 px-5 pb-5 pt-4">
          <p class="text-xs text-base-content/50 mb-3 font-mono bg-base-200/50 rounded-lg px-3 py-2">
            Columns: bib_number, split_short_name, elapsed_time
          </p>
          <form phx-submit="import_csv">
            <div class="fieldset mb-3">
              <textarea
                name="csv_text"
                rows="5"
                class="w-full textarea font-mono text-sm rounded-lg border-base-300 bg-base-200/30 focus:border-primary/50 focus:ring-primary/20"
                placeholder={"bib_number,split_short_name,elapsed_time\n101,swim,00:15:30\n102,swim,00:16:45"}
              >{@csv_text}</textarea>
            </div>
            <.button type="submit" variant="primary">
              <.icon name="hero-arrow-up-tray" class="size-4 mr-1" /> Import
            </.button>
          </form>

          <div :if={@import_result} class="mt-4 flex items-center gap-3 rounded-lg bg-success/5 border border-success/30 px-4 py-3">
            <.icon name="hero-check-circle" class="size-5 text-success shrink-0" />
            <p class="text-sm text-success font-semibold">
              Successfully imported {@import_result.imported} entries.
            </p>
          </div>

          <div :if={@import_errors != []} class="mt-4 rounded-lg bg-warning/5 border border-warning/30 px-4 py-3">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0" />
              <p class="text-sm text-warning font-semibold">Import errors</p>
            </div>
            <ul class="space-y-1 text-sm text-base-content/70 ml-7">
              <li :for={err <- @import_errors}>
                <span class="font-mono text-xs bg-base-200 rounded px-1 py-0.5">Row {err.row}</span>
                {err.message}
                <span class="text-base-content/40">({err.field})</span>
              </li>
            </ul>
          </div>
        </div>
      </details>
    </div>
    """
  end

  # --------------------------------------------------------------------------
  # Events
  # --------------------------------------------------------------------------

  @impl true
  def handle_event("start_race", _params, socket) do
    race = socket.assigns.race

    case Timing.start_race(%{race_id: race.id, started_at: DateTime.utc_now()}) do
      {:ok, race_start} ->
        {:ok, timer_ref} = :timer.send_interval(1_000, self(), :tick)

        {:noreply,
         socket
         |> assign(:race_start, race_start)
         |> assign(:elapsed_seconds, compute_elapsed_seconds(race_start))
         |> assign(:timer_ref, timer_ref)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Failed to start race.")}
    end
  end

  def handle_event("select_split", %{"split-id" => split_id}, socket) do
    split_id = String.to_integer(split_id)
    selected = Enum.find(socket.assigns.splits, &(&1.id == split_id))
    {:noreply, assign(socket, :selected_split, selected)}
  end

  def handle_event("update_bib", %{"bib" => bib}, socket) do
    {:noreply, assign(socket, :bib_input, bib)}
  end

  def handle_event("quick_bib", %{"bib" => bib}, socket) do
    {:noreply, assign(socket, :bib_input, bib)}
  end

  def handle_event("record_time", %{"bib" => bib}, socket) do
    bib = String.trim(bib)
    race = socket.assigns.race
    race_start = socket.assigns.race_start
    selected_split = socket.assigns.selected_split

    cond do
      bib == "" ->
        {:noreply, assign(socket, :error, "Please enter a bib number.")}

      is_nil(selected_split) ->
        {:noreply, assign(socket, :error, "Please select a split point.")}

      true ->
        case Participants.get_participant_by_bib(race.id, bib) do
          nil ->
            {:noreply, assign(socket, :error, "Unknown bib number: #{bib}")}

          participant ->
            now = DateTime.utc_now()
            elapsed_ms = DateTime.diff(now, race_start.started_at, :millisecond)

            attrs = %{
              participant_id: participant.id,
              split_id: selected_split.id,
              elapsed_ms: elapsed_ms,
              absolute_time: now,
              source: :manual
            }

            case Timing.record_split_time(attrs) do
              {:ok, _split_time} ->
                {:noreply,
                 socket
                 |> assign(:bib_input, "")
                 |> assign(:error, nil)}

              {:error, changeset} ->
                error_msg = format_changeset_error(changeset)
                {:noreply, assign(socket, :error, error_msg)}
            end
        end
    end
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    split_time = Timing.get_split_time!(id)

    case Timing.delete_split_time(split_time) do
      {:ok, _split_time} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Failed to delete entry.")}
    end
  end

  def handle_event("import_csv", %{"csv_text" => csv_text}, socket) do
    race = socket.assigns.race

    case CSVImport.import(csv_text, race.id) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:import_result, result)
         |> assign(:import_errors, [])
         |> assign(:csv_text, "")
         |> assign(:recent_entries, load_recent_entries(race.id))
         |> assign(:next_up, load_next_up(race.id))}

      {:error, errors} when is_list(errors) ->
        {:noreply,
         socket
         |> assign(:import_result, nil)
         |> assign(:import_errors, errors)
         |> assign(:csv_text, csv_text)}

      {:error, _other} ->
        {:noreply,
         socket
         |> assign(:import_result, nil)
         |> assign(:import_errors, [%{row: 0, field: "csv", message: "An unexpected error occurred"}])
         |> assign(:csv_text, csv_text)}
    end
  end

  # --------------------------------------------------------------------------
  # handle_info
  # --------------------------------------------------------------------------

  @impl true
  def handle_info(:tick, socket) do
    elapsed = compute_elapsed_seconds(socket.assigns.race_start)
    {:noreply, assign(socket, :elapsed_seconds, elapsed)}
  end

  def handle_info({:split_time_recorded, split_time}, socket) do
    split_time = preload_split_time(split_time)

    recent =
      [split_time | socket.assigns.recent_entries]
      |> Enum.take(10)

    {:noreply,
     socket
     |> assign(:recent_entries, recent)
     |> assign(:next_up, load_next_up(socket.assigns.race.id))}
  end

  def handle_info({:split_time_deleted, split_time}, socket) do
    recent =
      Enum.reject(socket.assigns.recent_entries, &(&1.id == split_time.id))

    {:noreply,
     socket
     |> assign(:recent_entries, recent)
     |> assign(:next_up, load_next_up(socket.assigns.race.id))}
  end

  # --------------------------------------------------------------------------
  # Private helpers
  # --------------------------------------------------------------------------

  defp compute_elapsed_seconds(nil), do: 0

  defp compute_elapsed_seconds(%{started_at: started_at}) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
    |> max(0)
  end

  defp format_elapsed(total_seconds) do
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    [hours, minutes, seconds]
    |> Enum.map(&String.pad_leading(Integer.to_string(&1), 2, "0"))
    |> Enum.join(":")
  end

  defp format_elapsed_ms(nil), do: "--:--:--"

  defp format_elapsed_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    frac = rem(ms, 1000)

    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    base =
      [hours, minutes, seconds]
      |> Enum.map(&String.pad_leading(Integer.to_string(&1), 2, "0"))
      |> Enum.join(":")

    "#{base}.#{String.pad_leading(Integer.to_string(frac), 3, "0")}"
  end

  defp load_next_up(race_id) do
    participants = Participants.list_participants(race_id)
    split_times = Timing.get_split_times_for_race(race_id)

    counts_by_participant =
      split_times
      |> Enum.group_by(& &1.participant_id)
      |> Enum.into(%{}, fn {pid, times} -> {pid, length(times)} end)

    participants
    |> Enum.filter(&(&1.status in [:registered, :racing]))
    |> Enum.map(fn p ->
      %{
        bib_number: p.bib_number,
        first_name: p.first_name,
        last_name: p.last_name,
        splits_completed: Map.get(counts_by_participant, p.id, 0)
      }
    end)
    |> Enum.sort_by(fn p -> {p.splits_completed, String.to_integer(p.bib_number)} end)
    |> Enum.take(10)
  end

  defp load_recent_entries(race_id) do
    Timing.get_split_times_for_race(race_id)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
    |> Enum.take(10)
  end

  defp preload_split_time(split_time) do
    Bibtime.Repo.preload(split_time, [:participant, :split])
  end

  defp format_changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp status_pill_class(status) do
    case status do
      :draft -> "bg-base-content/10 text-base-content/60"
      :registration_open -> "bg-info/15 text-info"
      :registration_closed -> "bg-warning/15 text-warning"
      :in_progress -> "bg-success/15 text-success"
      :finished -> "bg-accent/15 text-accent"
      :archived -> "bg-neutral/15 text-neutral"
      _ -> "bg-base-content/10 text-base-content/60"
    end
  end

  defp format_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
