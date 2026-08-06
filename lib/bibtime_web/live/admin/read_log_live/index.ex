defmodule BibtimeWeb.Admin.ReadLogLive.Index do
  @moduledoc """
  Live feed of every chip-read event for a race: recorded, duplicate
  (lockout or all-splits-done), and unmatched reads, in arrival order.

  Deliberately ephemeral — events are held in memory only and the feed
  starts when the page is opened. The durable copy is the `chip_read …`
  log line emitted per event by `Bibtime.Timing.ingest_chip_read/2`.
  """

  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Timing

  @max_events 300

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")
    end

    station_names =
      Map.new(Timing.list_all_stations(), fn station -> {station.id, station.name} end)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:station_names, station_names)
     |> assign(:filter, :all)
     |> assign(:all_events, [])
     |> stream(:events, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="flex items-start justify-between gap-6 pb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Read Log")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
        </div>
        <p class="text-xs text-base-content/40 max-w-xs text-right">
          {gettext("Live feed only — events are not stored and the list clears on refresh.")}
        </p>
      </div>

      <div class="mb-4 flex flex-wrap gap-2">
        <button
          :for={{filter, label} <- filter_options()}
          phx-click="set_filter"
          phx-value-filter={filter}
          class={[
            "btn btn-sm",
            if(@filter == filter, do: "btn-primary", else: "btn-ghost")
          ]}
        >
          {label}
          <span class="font-mono text-xs opacity-70">{count_for(@all_events, filter)}</span>
        </button>
      </div>

      <div class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm">
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">{gettext("Time (UTC)")}</th>
              <th class="font-semibold">{gettext("Station")}</th>
              <th class="font-semibold">{gettext("Outcome")}</th>
              <th class="font-semibold">{gettext("Participant")}</th>
              <th class="font-semibold">{gettext("Detail")}</th>
              <th class="font-semibold hidden lg:table-cell">{gettext("Chip")}</th>
            </tr>
          </thead>
          <tbody id="events" phx-update="stream">
            <tr
              :for={{dom_id, event} <- @streams.events}
              id={dom_id}
              class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
            >
              <td class="py-2.5 font-mono text-xs text-base-content/60">
                {format_time(event.at)}
              </td>
              <td class="py-2.5 text-sm">{event.station_name}</td>
              <td class="py-2.5">
                <span class={[
                  "inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium",
                  outcome_badge(event.status)
                ]}>
                  {outcome_label(event.status)}
                </span>
              </td>
              <td class="py-2.5 text-sm">
                <span :if={event.bib_number}>
                  <span class="font-mono font-bold text-primary">#{event.bib_number}</span>
                  <span class="text-base-content/70 ml-1">{event.participant_name}</span>
                </span>
                <span :if={!event.bib_number} class="text-base-content/30">—</span>
              </td>
              <td class="py-2.5 text-sm text-base-content/70">
                <span class="inline-flex items-center gap-1.5">
                  {event.detail}
                  <.icon
                    :if={event.needs_review}
                    name="hero-exclamation-triangle"
                    class="size-4 text-warning"
                  />
                </span>
              </td>
              <td class="py-2.5 font-mono text-xs text-base-content/40 hidden lg:table-cell">
                {event.chip_id}
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@all_events == []} class="flex flex-col items-center py-10 text-center">
          <.icon name="hero-signal" class="size-8 text-base-content/20 mb-2" />
          <p class="text-sm text-base-content/50">
            {gettext("Waiting for reads — events appear here as stations scan tags.")}
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter = safe_filter(filter)
    filtered = Enum.filter(socket.assigns.all_events, &matches_filter?(&1, filter))

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:events, filtered, reset: true)}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:station_read, station_id, payload}, socket) do
    event = build_event(station_id, payload, socket.assigns.station_names)

    all_events = Enum.take([event | socket.assigns.all_events], @max_events)
    socket = assign(socket, :all_events, all_events)

    socket =
      if matches_filter?(event, socket.assigns.filter) do
        stream_insert(socket, :events, event, at: 0, limit: @max_events)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:station_heartbeat, _station_id, _metadata}, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_event(station_id, payload, station_names) do
    %{
      id: "read-#{System.unique_integer([:positive])}",
      at: Map.get(payload, :at) || DateTime.utc_now(),
      station_name:
        Map.get(station_names, station_id) || gettext("Station #%{id}", id: station_id),
      status: payload.status,
      chip_id: Map.get(payload, :chip_id),
      bib_number: Map.get(payload, :bib_number),
      participant_name: Map.get(payload, :participant_name),
      needs_review: Map.get(payload, :needs_review, false),
      detail: detail(payload)
    }
  end

  defp detail(%{status: :recorded} = payload) do
    gettext("→ %{split} at %{elapsed}",
      split: payload.split_name,
      elapsed: format_elapsed_ms(payload.elapsed_ms)
    )
  end

  defp detail(%{status: :duplicate, reason: :lockout} = payload) do
    gettext("re-read %{s}s after last pass", s: payload.seconds_since_last)
  end

  defp detail(%{status: :duplicate}) do
    gettext("all splits already recorded")
  end

  defp detail(%{status: :unmatched}) do
    gettext("chip not assigned to any participant")
  end

  defp detail(_), do: ""

  defp matches_filter?(_event, :all), do: true
  defp matches_filter?(event, filter), do: event.status == filter

  defp safe_filter("recorded"), do: :recorded
  defp safe_filter("duplicate"), do: :duplicate
  defp safe_filter("unmatched"), do: :unmatched
  defp safe_filter(_), do: :all

  defp filter_options do
    [
      {:all, gettext("All")},
      {:recorded, gettext("Recorded")},
      {:duplicate, gettext("Duplicates")},
      {:unmatched, gettext("Unmatched")}
    ]
  end

  defp count_for(events, :all), do: length(events)
  defp count_for(events, filter), do: Enum.count(events, &(&1.status == filter))

  defp format_time(%DateTime{} = at) do
    Calendar.strftime(at, "%H:%M:%S")
  end

  defp format_time(_), do: "-"

  defp format_elapsed_ms(ms) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    [hours, minutes, seconds]
    |> Enum.map(&String.pad_leading(Integer.to_string(&1), 2, "0"))
    |> Enum.join(":")
  end

  defp format_elapsed_ms(_), do: "-"

  defp outcome_badge(:recorded), do: "bg-success/10 text-success"
  defp outcome_badge(:duplicate), do: "bg-warning/10 text-warning"
  defp outcome_badge(:unmatched), do: "bg-error/10 text-error"
  defp outcome_badge(_), do: "bg-base-200 text-base-content/50"

  defp outcome_label(:recorded), do: gettext("Recorded")
  defp outcome_label(:duplicate), do: gettext("Duplicate")
  defp outcome_label(:unmatched), do: gettext("Unmatched")
  defp outcome_label(other), do: to_string(other)
end
