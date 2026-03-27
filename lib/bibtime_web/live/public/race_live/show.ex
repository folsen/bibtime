defmodule BibtimeWeb.Public.RaceLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Photos
  alias Bibtime.Races
  alias Bibtime.Participants

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :splits])

    participants = Participants.list_participants(race.id)
    participant_count = Participants.count_participants(race.id)
    photo_count = Photos.count_photos(race.id)

    {:ok,
     assign(socket,
       race: race,
       participants: participants,
       participant_count: participant_count,
       photo_count: photo_count,
       page_title: race.name
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-10">
      <%!-- Hero section --%>
      <div class="rounded-xl bg-gradient-to-br from-primary/10 via-base-200 to-secondary/10 border border-base-300 px-8 py-10 mb-8">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-4xl sm:text-5xl font-bold tracking-tight text-base-content mb-3">
              {@race.name}
            </h1>
            <div class="flex flex-wrap items-center gap-3">
              <.status_pill
                status={@race.status}
                class="inline-flex items-center px-3 py-1 font-semibold tracking-wide uppercase"
              />
              <span
                :if={@participant_count > 0}
                class="inline-flex items-center gap-1.5 rounded-full bg-base-300/50 px-3 py-1 text-xs font-semibold text-base-content/70"
              >
                <.icon name="hero-users" class="size-3.5" />
                {ngettext("%{count} Registered", "%{count} Registered", @participant_count)}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Details cards --%>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <div
          :if={@race.date}
          class="rounded-lg bg-base-200/60 border border-base-300/50 px-5 py-4 flex items-center gap-3"
        >
          <div class="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10">
            <.icon name="hero-calendar" class="size-5 text-primary" />
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-base-content/50 font-medium">
              {gettext("Date")}
            </p>
            <p class="text-sm font-semibold text-base-content">
              {format_date(@race.date)}
            </p>
          </div>
        </div>
        <div
          :if={@race.location}
          class="rounded-lg bg-base-200/60 border border-base-300/50 px-5 py-4 flex items-center gap-3"
        >
          <div class="flex items-center justify-center w-10 h-10 rounded-full bg-secondary/10">
            <.icon name="hero-map-pin" class="size-5 text-secondary" />
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-base-content/50 font-medium">
              {gettext("Location")}
            </p>
            <p class="text-sm font-semibold text-base-content">{@race.location}</p>
          </div>
        </div>
        <div class="rounded-lg bg-base-200/60 border border-base-300/50 px-5 py-4 flex items-center gap-3">
          <div class="flex items-center justify-center w-10 h-10 rounded-full bg-accent/10">
            <.icon name="hero-tag" class="size-5 text-accent" />
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide text-base-content/50 font-medium">
              {gettext("Type")}
            </p>
            <p class="text-sm font-semibold text-base-content capitalize">{@race.race_type}</p>
          </div>
        </div>
      </div>

      <%!-- Description card --%>
      <div
        :if={@race.description}
        class="rounded-lg bg-base-200/40 border border-base-300/50 px-6 py-5 mb-8"
      >
        <h2 class="text-sm uppercase tracking-wide text-base-content/50 font-semibold mb-2">
          {gettext("About this race")}
        </h2>
        <p class="text-base-content/80 leading-relaxed">{@race.description}</p>
      </div>

      <%!-- CTA buttons --%>
      <div class="mb-10 flex flex-wrap gap-4">
        <.link
          :if={@race.status == :registration_open}
          navigate={~p"/races/#{@race.slug}/register"}
          class="btn btn-primary btn-lg gap-2 shadow-md hover:shadow-lg transition-shadow"
        >
          <.icon name="hero-pencil-square" class="size-5" /> {gettext("Register Now")}
          <.icon name="hero-arrow-right" class="size-5" />
        </.link>
        <.link
          navigate={~p"/races/#{@race.slug}/results"}
          class={[
            "btn btn-lg gap-2 shadow-md hover:shadow-lg transition-shadow",
            if(@race.status == :registration_open, do: "btn-outline btn-primary", else: "btn-primary")
          ]}
        >
          <.icon name="hero-trophy" class="size-5" /> {gettext("View Results")}
          <.icon name="hero-arrow-right" class="size-5" />
        </.link>
        <.link
          :if={@photo_count > 0}
          navigate={~p"/races/#{@race.slug}/photos"}
          class="btn btn-lg btn-outline gap-2 shadow-md hover:shadow-lg transition-shadow"
        >
          <.icon name="hero-photo" class="size-5" /> {gettext("View Photos")}
        </.link>
      </div>

      <%!-- Categories as pills --%>
      <div :if={@race.categories != []} class="mb-10">
        <h2 class="text-lg font-semibold text-base-content mb-4">{gettext("Categories")}</h2>
        <div class="flex flex-wrap gap-2">
          <span
            :for={category <- @race.categories}
            class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 text-primary border border-primary/20 px-4 py-1.5 text-sm font-medium"
          >
            {category.name}
            <span :if={category.distance_label} class="text-primary/60 text-xs font-normal">
              {category.distance_label}
            </span>
          </span>
        </div>
      </div>
      <%!-- Start List --%>
      <div :if={
        @race.status in [:registration_closed, :in_progress, :finished] and @participants != []
      }>
        <div class="flex items-center gap-3 mb-4">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Start List")}</h2>
          <span class="inline-flex items-center gap-1.5 rounded-full bg-base-300/50 px-3 py-1 text-xs font-semibold text-base-content/70">
            <.icon name="hero-users" class="size-3.5" />
            {ngettext("%{count} participant", "%{count} participants", @participant_count)}
          </span>
        </div>

        <div class="overflow-x-auto rounded-xl border border-base-300/50 bg-base-100">
          <table class="w-full border-separate border-spacing-0">
            <thead>
              <tr class="text-xs uppercase tracking-wider text-base-content/50">
                <th class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm w-16 px-3 py-3 font-semibold border-b border-base-300/50 text-left first:rounded-tl-xl">
                  {gettext("Bib")}
                </th>
                <th class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left">
                  {gettext("Name")}
                </th>
                <th class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left">
                  {gettext("Club")}
                </th>
                <th class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left last:rounded-tr-xl">
                  {gettext("Category")}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={participant <- @participants}
                class="even:bg-base-200/30 hover:bg-base-200/60 transition-colors"
              >
                <td class="font-mono text-sm px-3 py-2.5 border-b border-base-300/20 text-base-content/70">
                  {participant.bib_number}
                </td>
                <td class="font-medium px-3 py-2.5 border-b border-base-300/20 text-base-content">
                  {participant.first_name} {participant.last_name}
                </td>
                <td class="text-base-content/50 text-sm px-3 py-2.5 border-b border-base-300/20">
                  {participant.club || "\u2014"}
                </td>
                <td class="text-sm px-3 py-2.5 border-b border-base-300/20">
                  <span
                    :if={participant.race_category}
                    class="inline-flex items-center rounded-full bg-primary/8 text-primary/80 px-2 py-0.5 text-xs font-medium"
                  >
                    {participant.race_category.name}
                  </span>
                  <span :if={participant.race_category == nil} class="text-base-content/30">
                    &mdash;
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
