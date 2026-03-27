defmodule BibtimeWeb.Admin.RaceLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races

  @impl true
  def mount(_params, _session, socket) do
    races = Races.list_races()

    {:ok,
     socket
     |> assign(:race_count, length(races))
     |> stream(:races, races)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 pb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">{gettext("Races")}</h1>
        <p class="mt-1 text-sm text-base-content/60">
          {gettext("Manage your events, configure categories, and track progress.")}
        </p>
      </div>
      <.button navigate={~p"/admin/races/new"} variant="primary">
        <.icon name="hero-plus" class="size-4 mr-1" /> {gettext("New Race")}
      </.button>
    </div>

    <div
      :if={@race_count > 0}
      class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
    >
      <table class="table w-full">
        <thead>
          <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
            <th class="font-semibold">{gettext("Name")}</th>
            <th class="font-semibold">{gettext("Date")}</th>
            <th class="font-semibold">{gettext("Location")}</th>
            <th class="font-semibold">{gettext("Type")}</th>
            <th class="font-semibold">{gettext("Status")}</th>
            <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody id="races" phx-update="stream">
          <tr
            :for={{dom_id, race} <- @streams.races}
            id={dom_id}
            class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30 hover:bg-primary/5 transition-colors"
          >
            <td class="py-3">
              <.link
                navigate={~p"/admin/races/#{race.id}"}
                class="font-medium text-primary hover:text-primary/80 transition-colors"
              >
                {race.name}
              </.link>
            </td>
            <td class="py-3 text-sm text-base-content/70">
              {if race.date, do: format_date_short(race.date), else: "-"}
            </td>
            <td class="py-3 text-sm text-base-content/70">
              {race.location || "-"}
            </td>
            <td class="py-3 text-sm">
              <span class="capitalize text-base-content/70">{race.race_type}</span>
            </td>
            <td class="py-3">
              <span class={[
                "rounded-full px-2.5 py-0.5 text-xs font-medium",
                status_pill_class(race.status)
              ]}>
                {format_race_status(race.status)}
              </span>
            </td>
            <td class="py-3">
              <div class="flex items-center gap-3">
                <.link
                  navigate={~p"/admin/races/#{race.id}"}
                  class="text-sm font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  {gettext("View")}
                </.link>
                <.link
                  navigate={~p"/admin/races/#{race.id}/edit"}
                  class="text-sm font-medium text-secondary hover:text-secondary/80 transition-colors"
                >
                  {gettext("Edit")}
                </.link>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div :if={@race_count == 0} class="flex flex-col items-center justify-center py-16 text-center">
      <div class="rounded-full bg-primary/10 p-4 mb-4">
        <.icon name="hero-trophy" class="size-10 text-primary/40" />
      </div>
      <h3 class="text-lg font-semibold text-base-content/80 mb-1">{gettext("No races yet")}</h3>
      <p class="text-sm text-base-content/50 mb-6 max-w-sm">
        {gettext("Create your first race to start managing events, participants, and timing.")}
      </p>
      <.button navigate={~p"/admin/races/new"} variant="primary">
        <.icon name="hero-plus" class="size-4 mr-1" /> {gettext("Create Your First Race")}
      </.button>
    </div>
    """
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
end
