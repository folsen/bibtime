defmodule BibtimeWeb.Admin.StationLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Timing
  alias Bibtime.Timing.TimingStation

  @stale_threshold_seconds 30

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id, preload: [:splits])
    stations = Timing.list_stations_for_race(race.id)
    all_stations = Timing.list_all_stations()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:stations:#{race.id}")
      :timer.send_interval(10_000, self(), :tick)
    end

    splits = Enum.sort_by(race.splits, & &1.sort_order)

    assigned_map = Map.new(stations, fn s -> {s.assigned_split_id, s} end)

    unassigned_stations =
      Enum.filter(all_stations, fn s -> is_nil(s.assigned_split_id) end)

    unassigned_options = Enum.map(unassigned_stations, fn s -> {s.name, s.id} end)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:splits, splits)
     |> assign(:assigned_map, assigned_map)
     |> assign(:unassigned_options, unassigned_options)
     |> assign(:now, DateTime.utc_now())
     |> stream(:stations, stations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="flex items-start justify-between gap-6 pb-6">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Timing Stations")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
        </div>
        <.link
          navigate={~p"/admin/stations"}
          class="text-sm text-base-content/50 hover:text-primary transition-colors flex items-center gap-1"
        >
          <.icon name="hero-cog-6-tooth" class="size-3.5" /> {gettext("Manage all stations")}
        </.link>
      </div>

      <%!-- Split assignment cards --%>
      <div class="space-y-4">
        <div
          :for={split <- @splits}
          class="rounded-xl border border-base-300 bg-base-100 shadow-sm p-5"
        >
          <div class="flex items-center justify-between gap-4">
            <div>
              <h3 class="font-semibold text-base-content">{split.name}</h3>
              <p class="text-xs text-base-content/50 mt-0.5">
                {split.short_name} — {to_string(split.leg_type)}
              </p>
            </div>

            <%= if station = @assigned_map[split.id] do %>
              <div class="flex items-center gap-4">
                <div class="flex items-center gap-2">
                  <span class={[
                    "inline-block size-2.5 rounded-full",
                    status_color(station, @now)
                  ]} />
                  <span class="text-sm font-medium text-base-content">{station.name}</span>
                </div>
                <div class="text-xs text-base-content/50 font-mono">
                  {format_last_seen(station.last_seen_at, @now)}
                </div>
                <div class="text-xs text-base-content/50 font-mono">
                  {gettext("Reads: %{n}", n: get_metadata(station, "reads_total", "-"))}
                </div>
                <div class="text-xs text-base-content/60 font-mono">
                  {station.firmware_version || "-"}
                </div>
                <button
                  phx-click="unassign"
                  phx-value-station-id={station.id}
                  class="btn btn-xs btn-ghost text-error/70 hover:text-error"
                >
                  {gettext("Unassign")}
                </button>
              </div>
            <% else %>
              <div class="flex items-center gap-2">
                <form
                  phx-submit="assign"
                  id={"assign-split-#{split.id}"}
                  class="flex items-center gap-2"
                >
                  <input type="hidden" name="split_id" value={split.id} />
                  <select name="station_id" class="select select-sm select-bordered">
                    <option value="">{gettext("Select a station...")}</option>
                    <option :for={{name, id} <- @unassigned_options} value={id}>
                      {name}
                    </option>
                  </select>
                  <button type="submit" class="btn btn-sm btn-primary">
                    {gettext("Assign")}
                  </button>
                </form>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div
        :if={@splits == []}
        class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-6 text-center"
      >
        <p class="text-sm text-base-content/60">
          {gettext("This race has no splits yet. Add splits before assigning stations.")}
        </p>
      </div>

      <div
        :if={@unassigned_options == [] and @splits != []}
        class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-4 text-center"
      >
        <p class="text-sm text-base-content/60">
          {gettext("No unassigned stations available.")}
          <.link navigate={~p"/admin/stations"} class="text-primary hover:underline">
            {gettext("Create a new station")}
          </.link>
        </p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("assign", %{"station_id" => "", "split_id" => _}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Please select a station."))}
  end

  def handle_event("assign", %{"station_id" => station_id, "split_id" => split_id}, socket) do
    station = Timing.get_timing_station!(station_id)
    split = Enum.find(socket.assigns.splits, &(to_string(&1.id) == split_id))

    case Timing.assign_station(station, split) do
      {:ok, updated} ->
        updated = Bibtime.Repo.preload(updated, :assigned_split)

        {:noreply,
         socket
         |> refresh_assignments()
         |> stream_insert(:stations, updated)
         |> put_flash(:info, gettext("Station assigned to %{split}.", split: split.name))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to assign station."))}
    end
  end

  def handle_event("unassign", %{"station-id" => station_id}, socket) do
    station = Timing.get_timing_station!(station_id)

    case Timing.unassign_station(station) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> refresh_assignments()
         |> stream_delete(:stations, station)
         |> put_flash(:info, gettext("Station unassigned."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to unassign station."))}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub / ticks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> refresh_assignments()}
  end

  def handle_info({:station_heartbeat, station_id, _metadata}, socket) do
    case safe_get_station(station_id) do
      nil -> {:noreply, socket}
      station -> {:noreply, socket |> stream_insert(:stations, station) |> refresh_assignments()}
    end
  end

  def handle_info({:station_read, station_id, _payload}, socket) do
    case safe_get_station(station_id) do
      nil -> {:noreply, socket}
      station -> {:noreply, socket |> stream_insert(:stations, station) |> refresh_assignments()}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp refresh_assignments(socket) do
    race = socket.assigns.race
    stations = Timing.list_stations_for_race(race.id)
    all_stations = Timing.list_all_stations()

    assigned_map = Map.new(stations, fn s -> {s.assigned_split_id, s} end)

    unassigned_stations = Enum.filter(all_stations, fn s -> is_nil(s.assigned_split_id) end)
    unassigned_options = Enum.map(unassigned_stations, fn s -> {s.name, s.id} end)

    socket
    |> assign(:assigned_map, assigned_map)
    |> assign(:unassigned_options, unassigned_options)
  end

  defp safe_get_station(id) do
    case Bibtime.Repo.get(TimingStation, id) do
      nil -> nil
      station -> Bibtime.Repo.preload(station, :assigned_split)
    end
  end

  defp get_metadata(%{metadata: metadata}, key, default) when is_map(metadata) do
    Map.get(metadata, key, default)
  end

  defp get_metadata(_, _, default), do: default

  defp status_color(station, now) do
    cond do
      is_nil(station.last_seen_at) -> "bg-base-300"
      station.status == :error -> "bg-error"
      stale?(station.last_seen_at, now) -> "bg-warning"
      true -> "bg-success"
    end
  end

  defp stale?(last_seen_at, now) do
    DateTime.diff(now, last_seen_at, :second) > @stale_threshold_seconds
  end

  defp format_last_seen(nil, _now), do: gettext("never")

  defp format_last_seen(last_seen_at, now) do
    diff = DateTime.diff(now, last_seen_at, :second)

    cond do
      diff < 0 -> gettext("just now")
      diff < 5 -> gettext("just now")
      diff < 60 -> gettext("%{n}s ago", n: diff)
      diff < 3600 -> gettext("%{n}m ago", n: div(diff, 60))
      true -> gettext("%{n}h ago", n: div(diff, 3600))
    end
  end
end
