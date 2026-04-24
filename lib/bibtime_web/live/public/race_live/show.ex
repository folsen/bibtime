defmodule BibtimeWeb.Public.RaceLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Photos
  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Registration

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :splits])

    # Public start list hides pending-payment participants — their bib
    # isn't yet assigned and they haven't fully committed to the race.
    # Admin views use `list_participants` directly and see everyone.
    participants =
      race.id
      |> Participants.list_participants()
      |> Enum.reject(&is_nil(&1.bib_number))

    slots_taken = Participants.count_slots_taken(race.id)
    photo_count = Photos.count_photos(race.id)
    registration_full = Registration.registration_full?(race)
    user_registrations = user_registrations(socket.assigns.current_scope, race.id)

    {:ok,
     assign(socket,
       race: race,
       participants: participants,
       slots_taken: slots_taken,
       start_list_count: length(participants),
       photo_count: photo_count,
       registration_full: registration_full,
       user_registrations: user_registrations,
       page_title: race.name
     )}
  end

  defp user_registrations(%{user: %{id: user_id}}, race_id) when not is_nil(user_id) do
    now = DateTime.utc_now()

    user_id
    |> Participants.list_user_participants_in_race(race_id)
    |> Enum.split_with(fn p ->
      (p.status == :pending_payment and p.hold_expires_at) &&
        DateTime.compare(p.hold_expires_at, now) == :gt
    end)
    |> then(fn {pending, others} ->
      # Drop expired-hold pending rows from the banner — they're effectively
      # abandoned. The user can re-submit the form to refresh the hold,
      # which goes through `resume_pending_registration`.
      registered = Enum.filter(others, fn p -> not is_nil(p.bib_number) end)
      %{pending: pending, registered: registered}
    end)
  end

  defp user_registrations(_, _), do: %{pending: [], registered: []}

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
                :if={@slots_taken > 0}
                class="inline-flex items-center gap-1.5 rounded-full bg-base-300/50 px-3 py-1 text-xs font-semibold text-base-content/70"
              >
                <.icon name="hero-users" class="size-3.5" />
                <%= if @race.participant_limit do %>
                  {gettext("%{count} / %{limit} Registered",
                    count: @slots_taken,
                    limit: @race.participant_limit
                  )}
                <% else %>
                  {ngettext("%{count} Registered", "%{count} Registered", @slots_taken)}
                <% end %>
              </span>
              <span
                :if={@registration_full}
                class="inline-flex items-center gap-1.5 rounded-full bg-error/10 text-error border border-error/20 px-3 py-1 text-xs font-semibold"
              >
                <.icon name="hero-no-symbol" class="size-3.5" />
                {gettext("Registration Full")}
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

      <%!-- Registration full banner --%>
      <div
        :if={@race.status == :registration_open && @registration_full}
        class="rounded-lg bg-warning/10 border border-warning/20 px-5 py-4 mb-4 flex items-center gap-3"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 text-warning shrink-0" />
        <p class="text-sm font-medium text-base-content">
          {gettext("Registration is full. No more spots are available.")}
        </p>
      </div>

      <%!-- Pending-payment banner (logged-in user with an active hold) --%>
      <div
        :if={@user_registrations.pending != []}
        class="rounded-xl bg-warning/10 border border-warning/20 px-6 py-5 mb-6"
      >
        <div class="flex items-start gap-3 mb-3">
          <.icon name="hero-clock" class="size-6 text-warning shrink-0 mt-0.5" />
          <div class="flex-1 min-w-0">
            <h2 class="text-base font-semibold text-base-content">
              {gettext("Your spot is held — finish payment to confirm")}
            </h2>
            <p class="text-xs text-base-content/60 mt-0.5">
              {gettext("Your bib will be assigned once payment is received.")}
            </p>
          </div>
        </div>

        <ul class="space-y-2">
          <li
            :for={p <- @user_registrations.pending}
            class="flex items-center justify-between rounded-lg bg-base-100 border border-base-300/40 px-4 py-2.5"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="inline-flex items-center justify-center px-2.5 h-7 rounded-lg bg-warning/20 text-warning text-xs font-bold uppercase tracking-wide shrink-0">
                {gettext("Pending")}
              </span>
              <span class="font-medium text-base-content truncate">
                {p.first_name} {p.last_name}
              </span>
            </div>
            <.link
              navigate={~p"/races/#{@race.slug}/register/confirmation/#{p.id}"}
              class="btn btn-warning btn-sm gap-1 shrink-0"
            >
              {gettext("Finish Payment")} <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </li>
        </ul>
      </div>

      <%!-- Your registrations banner (logged-in + already registered) --%>
      <div
        :if={@user_registrations.registered != []}
        class="rounded-xl bg-success/10 border border-success/20 px-6 py-5 mb-6"
      >
        <div class="flex items-start gap-3 mb-3">
          <.icon name="hero-check-circle" class="size-6 text-success shrink-0 mt-0.5" />
          <div class="flex-1 min-w-0">
            <h2 class="text-base font-semibold text-base-content">
              {ngettext(
                "You're registered for this race",
                "You have %{count} registrations for this race",
                length(@user_registrations.registered),
                count: length(@user_registrations.registered)
              )}
            </h2>
          </div>
        </div>

        <ul class="space-y-2">
          <li
            :for={p <- @user_registrations.registered}
            class="flex items-center justify-between rounded-lg bg-base-100 border border-base-300/40 px-4 py-2.5"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="inline-flex items-center justify-center w-9 h-9 rounded-lg bg-primary/10 font-mono text-sm font-bold text-primary shrink-0">
                {p.bib_number}
              </span>
              <span class="font-medium text-base-content truncate">
                {p.first_name} {p.last_name}
              </span>
              <span
                :if={p.race_category}
                class="text-xs text-base-content/50 hidden sm:inline"
              >
                {p.race_category.name}
              </span>
            </div>
            <.link
              navigate={~p"/races/#{@race.slug}/my-registration/#{p.confirmation_token}"}
              class="btn btn-ghost btn-sm gap-1 shrink-0"
            >
              {gettext("View")} <.icon name="hero-arrow-right" class="size-4" />
            </.link>
          </li>
        </ul>
      </div>

      <%!-- CTA buttons --%>
      <div class="mb-10 flex flex-wrap gap-4">
        <.link
          :if={
            @race.status == :registration_open && !@registration_full &&
              @user_registrations.pending == [] && @user_registrations.registered == []
          }
          navigate={~p"/races/#{@race.slug}/register"}
          class="btn btn-primary btn-lg gap-2 shadow-md hover:shadow-lg transition-shadow"
        >
          <.icon name="hero-pencil-square" class="size-5" /> {gettext("Register Now")}
          <.icon name="hero-arrow-right" class="size-5" />
        </.link>
        <.link
          :if={
            @race.status == :registration_open && !@registration_full &&
              (@user_registrations.pending != [] or @user_registrations.registered != [])
          }
          navigate={~p"/races/#{@race.slug}/register"}
          class="btn btn-outline btn-primary gap-2"
        >
          <.icon name="hero-user-plus" class="size-5" />
          {gettext("Register another person")}
        </.link>
        <.link
          :if={@race.status in [:in_progress, :finished, :archived]}
          navigate={~p"/races/#{@race.slug}/results"}
          class="btn btn-lg btn-primary gap-2 shadow-md hover:shadow-lg transition-shadow"
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
      <div :if={@participants != []}>
        <div class="flex items-center gap-3 mb-4">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Start List")}</h2>
          <span class="inline-flex items-center gap-1.5 rounded-full bg-base-300/50 px-3 py-1 text-xs font-semibold text-base-content/70">
            <.icon name="hero-users" class="size-3.5" />
            {ngettext("%{count} participant", "%{count} participants", @start_list_count)}
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
                <th
                  :if={@race.categories != []}
                  class="sticky top-0 z-10 bg-base-200/80 backdrop-blur-sm px-3 py-3 font-semibold border-b border-base-300/50 text-left last:rounded-tr-xl"
                >
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
                <td
                  :if={@race.categories != []}
                  class="text-sm px-3 py-2.5 border-b border-base-300/20"
                >
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
