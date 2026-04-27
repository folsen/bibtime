defmodule BibtimeWeb.Public.MyRacesLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Participants

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    participants = Participants.list_participants_for_user(user.id)

    {:ok,
     assign(socket,
       participants: participants,
       page_title: gettext("My Races")
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-10">
      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-base-content mb-2">
          {gettext("My Races")}
        </h1>
        <p class="text-base-content/50">{gettext("Your race registrations and results")}</p>
      </div>

      <div
        :if={@participants == []}
        class="rounded-xl bg-base-200/60 border border-base-300/50 px-8 py-12 text-center"
      >
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-300/50 mb-4">
          <.icon name="hero-ticket" class="size-8 text-base-content/30" />
        </div>
        <h2 class="text-xl font-semibold text-base-content mb-2">
          {gettext("No registrations yet")}
        </h2>
        <p class="text-base-content/50 mb-6">{gettext("Find a race and register to see it here.")}</p>
      </div>

      <div :if={@participants != []} class="space-y-4">
        <div
          :for={participant <- @participants}
          class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden hover:shadow-md transition-shadow"
        >
          <div class="px-4 sm:px-6 py-4 sm:py-5 flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4">
            <div class="flex items-center gap-3 sm:gap-4 flex-1 min-w-0">
              <div class={[
                "flex items-center justify-center w-14 h-14 rounded-2xl border shrink-0",
                if(participant.bib_number,
                  do: "bg-primary/10 border-primary/20",
                  else: "bg-warning/10 border-warning/20"
                )
              ]}>
                <span
                  :if={participant.bib_number}
                  class="text-xl font-bold font-mono text-primary"
                >
                  {participant.bib_number}
                </span>
                <.icon
                  :if={is_nil(participant.bib_number)}
                  name="hero-clock"
                  class="size-6 text-warning"
                />
              </div>

              <div class="flex-1 min-w-0">
                <h2 class="text-lg font-semibold text-base-content truncate">
                  {participant.race.name}
                </h2>
                <div class="flex flex-wrap items-center gap-2 mt-1">
                  <span :if={participant.race.date} class="text-sm text-base-content/50">
                    {format_date(participant.race.date)}
                  </span>
                  <span
                    :if={participant.race_category}
                    class="inline-flex items-center rounded-full bg-primary/8 text-primary/80 px-2 py-0.5 text-xs font-medium"
                  >
                    {participant.race_category.name}
                  </span>
                  <span class={[
                    "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
                    status_class(participant.status)
                  ]}>
                    {format_participant_status(participant.status)}
                  </span>
                </div>
              </div>
            </div>

            <div class="flex items-center gap-2 sm:shrink-0">
              <.link
                :if={participant.race.status in [:registration_open, :registration_closed]}
                navigate={~p"/my-races/#{participant.id}/edit"}
                class="btn btn-outline btn-sm gap-1.5 flex-1 sm:flex-none"
              >
                <.icon name="hero-pencil-square" class="size-4" />
                {gettext("Edit")}
              </.link>
              <.link
                navigate={~p"/races/#{participant.race.slug}/results"}
                class="btn btn-outline btn-primary btn-sm gap-1.5 flex-1 sm:flex-none"
              >
                <.icon name="hero-trophy" class="size-4" />
                {gettext("Results")}
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_class(:registered), do: "bg-base-content/10 text-base-content/60"
  defp status_class(:checked_in), do: "bg-success/15 text-success"
  defp status_class(:racing), do: "bg-info/15 text-info"
  defp status_class(:finished), do: "bg-success/15 text-success"
  defp status_class(:dns), do: "bg-warning/15 text-warning"
  defp status_class(:dnf), do: "bg-error/15 text-error"
  defp status_class(:dsq), do: "bg-error/15 text-error"
  defp status_class(_), do: "bg-base-content/10 text-base-content/60"
end
