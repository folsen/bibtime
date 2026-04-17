defmodule BibtimeWeb.Public.PhotoLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Accounts.User
  alias Bibtime.Races
  alias Bibtime.Photos
  alias Bibtime.Participants

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race = Races.get_race_by_slug!(slug)
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    can_view? = can_view_photos?(race, user)

    {photos, participants} =
      if can_view? do
        {Photos.list_photos(race.id), Participants.list_participants(race.id)}
      else
        {[], []}
      end

    {:ok,
     assign(socket,
       race: race,
       can_view_photos: can_view?,
       photos: photos,
       participants: participants,
       filtered_photos: photos,
       search: "",
       lightbox_src: nil,
       page_title: gettext("Photos") <> " — " <> race.name
     )}
  end

  defp can_view_photos?(%{photos_public: true}, _user), do: true
  defp can_view_photos?(_race, nil), do: false

  defp can_view_photos?(race, %User{} = user) do
    User.admin?(user) or Participants.user_participant_in_race?(user.id, race.id)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    bib = params["bib"]

    {search, filtered_photos} =
      case bib do
        nil ->
          {"", socket.assigns.photos}

        bib_number ->
          filtered =
            Enum.filter(socket.assigns.photos, fn photo ->
              bib_number in (photo.bib_numbers || [])
            end)

          {bib_number, filtered}
      end

    {:noreply, assign(socket, search: search, filtered_photos: filtered_photos)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%!-- Header --%>
      <div class="mb-8 flex items-start gap-4">
        <div class="w-1 self-stretch rounded-full bg-gradient-to-b from-primary via-secondary to-accent shrink-0">
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-3 mb-1">
            <.link
              navigate={~p"/races/#{@race.slug}"}
              class="flex items-center justify-center w-8 h-8 rounded-full bg-base-200 text-base-content/50 hover:text-base-content hover:bg-base-300 transition-colors"
            >
              <.icon name="hero-arrow-left" class="size-4" />
            </.link>
            <h1 class="text-2xl sm:text-3xl font-bold tracking-tight text-base-content truncate">
              {gettext("Photos")}
            </h1>
          </div>
          <p class="text-sm text-base-content/50 ml-11">
            {@race.name}
            {if @race.date, do: " — #{format_date(@race.date)}", else: ""}
          </p>
        </div>
      </div>

      <%!-- Restricted access notice --%>
      <div :if={!@can_view_photos} class="text-center py-16">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
          <.icon name="hero-lock-closed" class="size-8 text-base-content/40" />
        </div>
        <p class="text-lg font-medium text-base-content mb-2">
          {gettext("Photos are only available to race participants")}
        </p>
        <p
          :if={!@current_scope || !@current_scope.user}
          class="text-sm text-base-content/60 max-w-md mx-auto mb-6"
        >
          {gettext(
            "If you are registered for this race, please log in with the email address you used to sign up to view the photos."
          )}
        </p>
        <p
          :if={@current_scope && @current_scope.user}
          class="text-sm text-base-content/60 max-w-md mx-auto mb-6"
        >
          {gettext(
            "You need to be registered for this race to view its photos. If you registered with a different email address, please log in with that one instead."
          )}
        </p>
        <.link
          :if={!@current_scope || !@current_scope.user}
          navigate={~p"/users/log-in"}
          class="btn btn-primary"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4 mr-1" />
          {gettext("Log in")}
        </.link>
      </div>

      <%!-- Search --%>
      <div :if={@can_view_photos} class="mb-6">
        <form phx-change="search" phx-submit="search" class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="size-5 text-base-content/30 absolute left-3 top-1/2 -translate-y-1/2"
          />
          <input
            type="text"
            name="search"
            value={@search}
            placeholder={gettext("Filter by bib number or name...")}
            phx-debounce="300"
            class="input input-bordered w-full pl-10 max-w-md"
          />
        </form>
      </div>

      <%!-- Photo grid --%>
      <div
        :if={@can_view_photos && @filtered_photos != []}
        class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3"
      >
        <div
          :for={photo <- @filtered_photos}
          class="relative group cursor-pointer rounded-lg overflow-hidden aspect-square bg-base-200"
          phx-click="open_lightbox"
          phx-value-src={photo.file_path}
        >
          <img
            src={photo.file_path}
            alt={photo.caption || photo.original_filename}
            class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
            loading="lazy"
          />
          <div
            :if={photo.bib_numbers != []}
            class="absolute bottom-1.5 left-1.5 flex flex-wrap gap-1"
          >
            <span
              :for={bib <- photo.bib_numbers}
              class="bg-black/70 text-white text-xs font-mono px-1.5 py-0.5 rounded"
            >
              #{bib}
            </span>
          </div>
          <div
            :if={photo.caption}
            class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-2 pt-6 opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <p class="text-white text-xs truncate">{photo.caption}</p>
          </div>
        </div>
      </div>

      <%!-- Empty state --%>
      <div :if={@can_view_photos && @filtered_photos == [] && @search != ""} class="text-center py-16">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
          <.icon name="hero-magnifying-glass" class="size-8 text-base-content/30" />
        </div>
        <p class="text-lg font-medium text-base-content/50 mb-1">
          {gettext("No photos found")}
        </p>
        <p class="text-sm text-base-content/40">
          {gettext("Try a different bib number or name.")}
        </p>
      </div>

      <div :if={@can_view_photos && @photos == [] && @search == ""} class="text-center py-16">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
          <.icon name="hero-photo" class="size-8 text-base-content/30" />
        </div>
        <p class="text-lg font-medium text-base-content/50 mb-1">
          {gettext("No photos yet")}
        </p>
        <p class="text-sm text-base-content/40">
          {gettext("Photos will appear here once they're uploaded.")}
        </p>
      </div>

      <%!-- Stats footer --%>
      <div
        :if={@can_view_photos && @filtered_photos != []}
        class="mt-6 flex flex-wrap items-center gap-3"
      >
        <div class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2">
          <.icon name="hero-photo" class="size-4 text-primary/60" />
          <span class="text-sm font-medium text-base-content/70">
            {ngettext("%{count} photo", "%{count} photos", length(@filtered_photos))}
          </span>
        </div>
        <div class="ml-auto">
          <.link
            navigate={~p"/races/#{@race.slug}/results"}
            class="inline-flex items-center gap-2 rounded-lg bg-base-200/50 border border-base-300/40 px-4 py-2 text-sm font-medium text-base-content/70 hover:bg-base-300/50 hover:text-base-content transition-colors"
          >
            <.icon name="hero-trophy" class="size-4" /> {gettext("Results")}
          </.link>
        </div>
      </div>

      <%!-- Lightbox --%>
      <div
        :if={@lightbox_src}
        class="fixed inset-0 z-50 bg-black/90 flex items-center justify-center"
        phx-click="close_lightbox"
        phx-window-keydown="close_lightbox"
        phx-key="Escape"
      >
        <button
          class="absolute top-4 right-4 text-white/70 hover:text-white z-10"
          phx-click="close_lightbox"
        >
          <.icon name="hero-x-mark" class="size-8" />
        </button>
        <img
          src={@lightbox_src}
          class="max-w-[90vw] max-h-[90vh] object-contain"
          phx-click-away="close_lightbox"
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    filtered =
      cond do
        term == "" ->
          socket.assigns.photos

        true ->
          search_term = String.downcase(term)

          # Find matching bib numbers from participant names
          matching_bibs =
            socket.assigns.participants
            |> Enum.filter(fn p ->
              name = String.downcase("#{p.first_name} #{p.last_name}")
              String.contains?(name, search_term)
            end)
            |> Enum.map(& &1.bib_number)

          socket.assigns.photos
          |> Enum.filter(fn photo ->
            bib_match =
              Enum.any?(photo.bib_numbers || [], fn bib ->
                String.contains?(String.downcase(bib), search_term)
              end)

            name_match =
              Enum.any?(photo.bib_numbers || [], fn bib ->
                bib in matching_bibs
              end)

            caption_match =
              photo.caption &&
                String.contains?(String.downcase(photo.caption), search_term)

            bib_match || name_match || caption_match
          end)
      end

    {:noreply, assign(socket, search: term, filtered_photos: filtered)}
  end

  @impl true
  def handle_event("open_lightbox", %{"src" => src}, socket) do
    {:noreply, assign(socket, lightbox_src: src)}
  end

  @impl true
  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, lightbox_src: nil)}
  end
end
