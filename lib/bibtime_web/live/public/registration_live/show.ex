defmodule BibtimeWeb.Public.RegistrationLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants

  @impl true
  def mount(%{"slug" => slug, "participant_id" => participant_id}, _session, socket) do
    race = Races.get_race_by_slug!(slug)

    participant =
      Participants.get_participant!(participant_id) |> Bibtime.Repo.preload(:race_category)

    {:ok,
     assign(socket,
       race: race,
       participant: participant,
       page_title: "Registration Confirmed — #{race.name}"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-10">
      <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden">
        <%!-- Success banner --%>
        <div class="bg-success/10 border-b border-success/20 px-8 py-6 text-center">
          <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-success/20 mb-3">
            <.icon name="hero-check-circle" class="size-8 text-success" />
          </div>
          <h1 class="text-2xl font-bold text-base-content mb-1">You're Registered!</h1>
          <p class="text-base-content/60 text-sm">
            A confirmation email has been sent to {@participant.email}
          </p>
        </div>

        <%!-- Details --%>
        <div class="px-8 py-6 space-y-5">
          <%!-- Bib number highlight --%>
          <div class="text-center py-4">
            <p class="text-xs uppercase tracking-widest text-base-content/40 font-semibold mb-2">
              Your Bib Number
            </p>
            <span class="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-primary/10 border-2 border-primary/30">
              <span class="text-3xl font-bold font-mono text-primary">{@participant.bib_number}</span>
            </span>
          </div>

          <div class="divide-y divide-base-300/30">
            <div class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Race</span>
              <span class="text-sm font-medium text-base-content">{@race.name}</span>
            </div>
            <div :if={@race.date} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Date</span>
              <span class="text-sm font-medium text-base-content">
                {Calendar.strftime(@race.date, "%B %d, %Y")}
              </span>
            </div>
            <div :if={@race.location} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Location</span>
              <span class="text-sm font-medium text-base-content">{@race.location}</span>
            </div>
            <div class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Name</span>
              <span class="text-sm font-medium text-base-content">
                {@participant.first_name} {@participant.last_name}
              </span>
            </div>
            <div :if={@participant.race_category} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Category</span>
              <span class="text-sm font-medium text-base-content">
                {@participant.race_category.name}
              </span>
            </div>
            <div :if={@participant.club} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Club</span>
              <span class="text-sm font-medium text-base-content">{@participant.club}</span>
            </div>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="px-8 py-5 bg-base-200/30 border-t border-base-300/30 flex flex-wrap gap-3">
          <.link
            navigate={~p"/races/#{@race.slug}"}
            class="btn btn-outline btn-primary btn-sm gap-1.5"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Race Page
          </.link>
          <.link
            navigate={~p"/races/#{@race.slug}/results"}
            class="btn btn-outline btn-sm gap-1.5"
          >
            <.icon name="hero-trophy" class="size-4" /> View Results
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
