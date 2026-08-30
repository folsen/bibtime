defmodule BibtimeWeb.Public.PhotoLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Photos
  alias Bibtime.Participants

  @max_entries 10
  @max_file_size 10_000_000

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race = Races.get_visible_race_by_slug!(slug, socket.assigns.current_scope)
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    can_view? = Photos.can_view?(race, user)
    can_upload? = Photos.can_upload?(race, user)

    {photos, participants} =
      if can_view? do
        {Photos.list_photos(race.id), Participants.list_participants(race.id)}
      else
        {[], []}
      end

    {:ok,
     socket
     |> assign(
       race: race,
       can_view_photos: can_view?,
       can_upload: can_upload?,
       photos: photos,
       participants: participants,
       filtered_photos: photos,
       search: "",
       lightbox_src: nil,
       upload_open: false,
       upload_caption: "",
       upload_bibs: own_bib_numbers(participants, user),
       max_entries: @max_entries,
       page_title: gettext("Photos") <> " — " <> race.name
     )
     |> assign_own_photos()
     |> allow_upload(:submissions,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: @max_entries,
       max_file_size: @max_file_size
     )}
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
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

        <%!-- Contribute panel --%>
        <div :if={@can_view_photos && @can_upload} class="mb-6">
          <button
            :if={!@upload_open}
            phx-click="open_upload"
            class="w-full flex items-center gap-3 rounded-xl border border-dashed border-base-300 hover:border-primary/50 hover:bg-primary/5 px-4 py-3 text-left transition-colors"
          >
            <span class="flex items-center justify-center w-9 h-9 rounded-full bg-primary/10 text-primary shrink-0">
              <.icon name="hero-arrow-up-tray" class="size-4" />
            </span>
            <span class="min-w-0">
              <span class="block text-sm font-medium text-base-content">
                {gettext("Add your photos")}
              </span>
              <span class="block text-xs text-base-content/50">
                {gettext(
                  "Share your shots from this race — an organizer reviews them before they appear."
                )}
              </span>
            </span>
          </button>

          <form
            :if={@upload_open}
            id="submission-form"
            phx-submit="submit_photos"
            phx-change="validate_submissions"
            class="rounded-xl border border-base-300 bg-base-100 p-4 sm:p-5"
          >
            <div class="flex items-start justify-between gap-3 mb-4">
              <div>
                <h2 class="text-sm font-semibold text-base-content">
                  {gettext("Add your photos")}
                </h2>
                <p class="text-xs text-base-content/50 mt-0.5">
                  {gettext(
                    "An organizer reviews every submission. Approved photos join the gallery for everyone."
                  )}
                </p>
              </div>
              <button
                type="button"
                phx-click="close_upload"
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Close")}
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div
              phx-drop-target={@uploads.submissions.ref}
              class={[
                "border-2 border-dashed rounded-xl p-6 text-center transition-colors",
                if(@uploads.submissions.entries != [],
                  do: "border-primary/50 bg-primary/5",
                  else: "border-base-300 hover:border-primary/40"
                )
              ]}
            >
              <.icon name="hero-photo" class="size-10 mx-auto text-base-content/25 mb-2" />
              <p class="text-sm text-base-content/60 mb-3">
                {gettext("Drag photos here or click to browse")}
              </p>
              <label for={@uploads.submissions.ref} class="btn btn-primary btn-sm cursor-pointer">
                {gettext("Choose Files")}
              </label>
              <.live_file_input upload={@uploads.submissions} class="sr-only" />
              <p class="text-xs text-base-content/40 mt-3">
                {gettext("JPG, PNG or WebP — up to %{count} files, 10MB each.", count: @max_entries)}
              </p>
            </div>

            <p :for={err <- upload_errors(@uploads.submissions)} class="text-xs text-error mt-2">
              {upload_error_message(err)}
            </p>

            <%!-- Selected files --%>
            <div :if={@uploads.submissions.entries != []} class="mt-4">
              <div class="grid grid-cols-3 sm:grid-cols-5 gap-3">
                <div :for={entry <- @uploads.submissions.entries} class="relative group">
                  <.live_img_preview
                    entry={entry}
                    class="w-full aspect-square object-cover rounded-lg bg-base-200"
                  />
                  <button
                    type="button"
                    phx-click="cancel_submission"
                    phx-value-ref={entry.ref}
                    class="absolute top-1 right-1 btn btn-circle btn-xs bg-black/50 border-0 text-white opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity"
                    aria-label={gettext("Cancel")}
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                  <div
                    :if={entry.progress > 0 && entry.progress < 100}
                    class="absolute bottom-0 left-0 right-0 h-1 bg-base-300 rounded-b-lg overflow-hidden"
                  >
                    <div class="h-full bg-primary transition-all" style={"width: #{entry.progress}%"} />
                  </div>
                  <p
                    :for={err <- upload_errors(@uploads.submissions, entry)}
                    class="text-xs text-error mt-0.5"
                  >
                    {upload_error_message(err)}
                  </p>
                </div>
              </div>

              <div class="grid sm:grid-cols-2 gap-3 mt-4">
                <div>
                  <label for="submission-caption" class="text-xs font-medium text-base-content/60">
                    {gettext("Caption")}
                  </label>
                  <input
                    id="submission-caption"
                    type="text"
                    name="caption"
                    value={@upload_caption}
                    maxlength="300"
                    placeholder={gettext("Optional — applies to all selected photos")}
                    class="input input-sm input-bordered w-full mt-0.5"
                  />
                </div>
                <div>
                  <label for="submission-bibs" class="text-xs font-medium text-base-content/60">
                    {gettext("Bib numbers in these photos")}
                  </label>
                  <input
                    id="submission-bibs"
                    type="text"
                    name="bib_numbers"
                    value={@upload_bibs}
                    placeholder={gettext("e.g. 101, 203, 45")}
                    class="input input-sm input-bordered w-full mt-0.5"
                  />
                </div>
              </div>

              <div class="flex justify-end mt-4">
                <button type="submit" class="btn btn-primary btn-sm">
                  <.icon name="hero-arrow-up-tray" class="size-4 mr-1" />
                  {ngettext(
                    "Submit %{count} photo",
                    "Submit %{count} photos",
                    length(@uploads.submissions.entries)
                  )}
                </button>
              </div>
            </div>
          </form>
        </div>

        <%!-- Invitation to log in so participants can contribute --%>
        <div
          :if={
            @can_view_photos && !@can_upload && @race.photo_uploads_enabled &&
              @race.status in [:in_progress, :finished] && (!@current_scope || !@current_scope.user)
          }
          class="mb-6 flex items-center gap-3 rounded-xl border border-base-300 bg-base-200/40 px-4 py-3"
        >
          <.icon name="hero-camera" class="size-5 text-base-content/40 shrink-0" />
          <p class="text-sm text-base-content/60">
            {gettext("Took photos at this race?")}
            <.link navigate={~p"/users/log-in"} class="link link-primary">
              {gettext("Log in as a participant")}
            </.link>
            {gettext("to add them to the gallery.")}
          </p>
        </div>

        <%!-- The user's own submissions still awaiting review --%>
        <div :if={@can_view_photos && @own_photos != []} class="mb-8">
          <h2 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-3">
            {gettext("Your submissions")}
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            <div
              :for={photo <- @own_photos}
              id={"own-photo-#{photo.id}"}
              class="relative rounded-lg overflow-hidden bg-base-200"
            >
              <img
                src={Photos.display_url(photo)}
                alt={photo.caption || photo.original_filename}
                class={[
                  "w-full aspect-square object-cover cursor-pointer",
                  photo.status == :rejected && "opacity-50 grayscale"
                ]}
                loading="lazy"
                phx-click="open_lightbox"
                phx-value-src={Photos.display_url(photo)}
              />
              <span class={[
                "absolute top-1.5 left-1.5 text-xs font-medium px-2 py-0.5 rounded-full",
                photo.status == :pending && "bg-warning/90 text-warning-content",
                photo.status == :rejected && "bg-error/90 text-error-content"
              ]}>
                {photo_status_label(photo.status)}
              </span>
              <button
                :if={photo.status == :pending}
                phx-click="withdraw_photo"
                phx-value-id={photo.id}
                data-confirm={gettext("Withdraw this photo?")}
                class="absolute top-1.5 right-1.5 btn btn-circle btn-xs bg-black/50 border-0 text-white"
                aria-label={gettext("Withdraw")}
              >
                <.icon name="hero-trash" class="size-3" />
              </button>
              <p
                :if={photo.status == :rejected && photo.rejection_reason}
                class="absolute bottom-0 left-0 right-0 bg-black/70 text-white text-xs px-2 py-1"
              >
                {photo.rejection_reason}
              </p>
            </div>
          </div>
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
            phx-value-src={Photos.display_url(photo)}
          >
            <img
              src={Photos.display_url(photo)}
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
        <div
          :if={@can_view_photos && @filtered_photos == [] && @search != ""}
          class="text-center py-16"
        >
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
          <p :if={!@can_upload} class="text-sm text-base-content/40">
            {gettext("Photos will appear here once they're uploaded.")}
          </p>
          <p :if={@can_upload} class="text-sm text-base-content/40">
            {gettext("Be the first — add your own photos from the race.")}
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
    </Layouts.app>
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

  @impl true
  def handle_event("open_upload", _params, socket) do
    {:noreply, assign(socket, upload_open: true)}
  end

  @impl true
  def handle_event("close_upload", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.submissions.entries, socket, fn entry, acc ->
        cancel_upload(acc, :submissions, entry.ref)
      end)

    {:noreply, assign(socket, upload_open: false)}
  end

  @impl true
  def handle_event("validate_submissions", params, socket) do
    {:noreply,
     assign(socket,
       upload_caption: params["caption"] || socket.assigns.upload_caption,
       upload_bibs: params["bib_numbers"] || socket.assigns.upload_bibs
     )}
  end

  @impl true
  def handle_event("cancel_submission", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :submissions, ref)}
  end

  @impl true
  def handle_event("submit_photos", params, socket) do
    %{race: race} = socket.assigns
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    # Re-check here, not just at mount: LiveView events are user-controlled and
    # the race may have been closed to uploads since the page loaded.
    race = Races.get_race!(race.id)

    if Photos.can_upload?(race, user) do
      attrs = %{
        caption: params["caption"],
        bib_numbers: parse_bibs(params["bib_numbers"])
      }

      results =
        consume_uploaded_entries(socket, :submissions, fn %{path: path}, entry ->
          {:ok, Photos.submit_photo(race, user, entry, path, attrs)}
        end)

      {ok, failed} = Enum.split_with(results, &match?({:ok, _}, &1))

      # One notice per batch, not one per file.
      Photos.notify_pending_submissions(race, length(ok))

      {:noreply,
       socket
       |> assign(race: race, upload_caption: "")
       |> assign_own_photos()
       |> flash_submission_result(length(ok), failed)}
    else
      {:noreply,
       socket
       |> assign(race: race, can_upload: false, upload_open: false)
       |> put_flash(:error, gettext("Photo uploads are not open for this race."))}
    end
  end

  @impl true
  def handle_event("withdraw_photo", %{"id" => id}, socket) do
    photo = Photos.get_photo!(id)
    user = socket.assigns.current_scope && socket.assigns.current_scope.user

    # Only the uploader may withdraw, and only while it is still pending.
    if user && photo.uploaded_by_user_id == user.id && photo.status == :pending do
      Photos.delete_photo(photo)

      {:noreply,
       socket
       |> assign_own_photos()
       |> put_flash(:info, gettext("Photo withdrawn."))}
    else
      {:noreply, put_flash(socket, :error, gettext("Could not withdraw that photo."))}
    end
  end

  defp assign_own_photos(socket) do
    user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    own =
      if user do
        socket.assigns.race.id
        |> Photos.list_own_photos(user.id)
        |> Enum.reject(&(&1.status == :approved))
      else
        []
      end

    assign(socket, own_photos: own)
  end

  defp flash_submission_result(socket, 0, failed) do
    put_flash(socket, :error, submission_error_message(failed))
  end

  defp flash_submission_result(socket, count, []) do
    put_flash(
      socket,
      :info,
      ngettext(
        "%{count} photo submitted — an organizer will review it shortly.",
        "%{count} photos submitted — an organizer will review them shortly.",
        count
      )
    )
  end

  defp flash_submission_result(socket, count, failed) do
    socket
    |> put_flash(
      :info,
      ngettext(
        "%{count} photo submitted for review.",
        "%{count} photos submitted for review.",
        count
      )
    )
    |> put_flash(:error, submission_error_message(failed))
  end

  defp submission_error_message(failed) do
    reason =
      failed
      |> Enum.map(fn
        {:error, reason} -> reason
        _ -> :unknown
      end)
      |> List.first()

    case reason do
      :rate_limited ->
        gettext("You've uploaded a lot of photos recently. Please try again later.")

      :pending_limit_reached ->
        gettext(
          "You already have photos waiting for review. Please wait for those to be reviewed."
        )

      :unsupported_type ->
        gettext("Some files weren't recognised as images and were skipped.")

      _ ->
        gettext("Some photos could not be uploaded. Please try again.")
    end
  end

  defp parse_bibs(nil), do: []

  defp parse_bibs(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(20)
  end

  defp own_bib_numbers(participants, nil) when is_list(participants), do: ""

  defp own_bib_numbers(participants, user) do
    participants
    |> Enum.filter(&(&1.user_id == user.id))
    |> Enum.map(& &1.bib_number)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp photo_status_label(:pending), do: gettext("Pending review")
  defp photo_status_label(:rejected), do: gettext("Not published")
  defp photo_status_label(_), do: gettext("Published")

  defp upload_error_message(:too_large), do: gettext("File is too large (max 10MB)")
  defp upload_error_message(:too_many_files), do: gettext("Too many files (max 10)")
  defp upload_error_message(:not_accepted), do: gettext("Invalid file type")
  defp upload_error_message(_), do: gettext("Upload error")
end
