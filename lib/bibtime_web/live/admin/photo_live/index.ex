defmodule BibtimeWeb.Admin.PhotoLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Photos
  alias Bibtime.AuditLog

  @filters ~w(pending approved rejected all)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    splits = Races.list_splits(race.id)

    {:ok,
     socket
     |> assign(
       race: race,
       splits: splits,
       page_title: gettext("Photos") <> " — " <> race.name,
       editing_photo_id: nil,
       rejecting_photo_id: nil,
       selected: MapSet.new()
     )
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 20,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pending_count = Photos.count_pending_photos(socket.assigns.race.id)
    filter = normalize_filter(params["status"], pending_count)

    {:noreply,
     socket
     |> assign(filter: filter, pending_count: pending_count)
     |> assign(pending_photo_count: pending_count)
     |> assign(selected: MapSet.new())
     |> load_photos()}
  end

  # Land on the review queue when there is something to review.
  defp normalize_filter(status, _pending) when status in @filters, do: status
  defp normalize_filter(_status, 0), do: "approved"
  defp normalize_filter(_status, _pending), do: "pending"

  defp load_photos(socket) do
    photos =
      Photos.list_photos(socket.assigns.race.id,
        status: filter_status(socket.assigns.filter),
        preload: :uploaded_by
      )

    assign(socket, photos: photos)
  end

  defp filter_status("all"), do: :all
  defp filter_status("pending"), do: :pending
  defp filter_status("rejected"), do: :rejected
  defp filter_status(_), do: :approved

  defp refresh(socket) do
    socket
    |> then(fn socket ->
      count = Photos.count_pending_photos(socket.assigns.race.id)
      assign(socket, pending_count: count, pending_photo_count: count)
    end)
    |> load_photos()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Photos")}
        </h1>
        <p class="text-sm text-base-content/50 mt-1">
          {ngettext("%{count} photo", "%{count} photos", length(@photos))}
          <span :if={@pending_count > 0} class="text-warning font-medium">
            — {ngettext(
              "%{count} awaiting review",
              "%{count} awaiting review",
              @pending_count
            )}
          </span>
        </p>
      </div>
    </div>

    <%!-- Upload area --%>
    <form id="upload-form" phx-submit="save_uploads" phx-change="validate_uploads">
      <div
        phx-drop-target={@uploads.photos.ref}
        class={[
          "border-2 border-dashed rounded-xl p-8 text-center transition-colors mb-6",
          if(@uploads.photos.entries != [],
            do: "border-primary/50 bg-primary/5",
            else: "border-base-300 hover:border-primary/40"
          )
        ]}
      >
        <.icon name="hero-photo" class="size-12 mx-auto text-base-content/25 mb-3" />
        <p class="text-base-content/60 mb-3">
          {gettext("Drag photos here or click to browse")}
        </p>
        <label
          for={@uploads.photos.ref}
          class="btn btn-primary btn-sm cursor-pointer"
        >
          {gettext("Choose Files")}
        </label>
        <.live_file_input upload={@uploads.photos} class="sr-only" />
      </div>

      <%!-- Upload preview --%>
      <div :if={@uploads.photos.entries != []} class="mb-6">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-sm font-semibold text-base-content/70">
            {ngettext(
              "%{count} file selected",
              "%{count} files selected",
              length(@uploads.photos.entries)
            )}
          </h2>
          <button type="submit" class="btn btn-primary btn-sm">
            <.icon name="hero-arrow-up-tray" class="size-4 mr-1" />
            {gettext("Upload All")}
          </button>
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-3">
          <div :for={entry <- @uploads.photos.entries} class="relative group">
            <.live_img_preview
              entry={entry}
              class="w-full aspect-square object-cover rounded-lg bg-base-200"
            />
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="absolute top-1 right-1 btn btn-circle btn-xs bg-black/50 border-0 text-white opacity-0 group-hover:opacity-100 transition-opacity"
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
            <p class="text-xs text-base-content/50 truncate mt-1">{entry.client_name}</p>
            <p :for={err <- upload_errors(@uploads.photos, entry)} class="text-xs text-error mt-0.5">
              {upload_error_message(err)}
            </p>
          </div>
        </div>
      </div>
    </form>

    <%!-- Status filter --%>
    <div class="flex flex-wrap items-center gap-2 mb-4">
      <.link
        :for={{value, label} <- filter_tabs(@pending_count)}
        patch={~p"/admin/races/#{@race.id}/photos?#{[status: value]}"}
        class={[
          "px-3 py-1.5 rounded-lg text-sm font-medium transition-colors",
          if(@filter == value,
            do: "bg-primary text-primary-content",
            else: "bg-base-200 text-base-content/60 hover:bg-base-300 hover:text-base-content"
          )
        ]}
      >
        {label}
      </.link>

      <div :if={@filter == "pending" && @photos != []} class="ml-auto flex items-center gap-2">
        <button
          :if={MapSet.size(@selected) > 0}
          phx-click="approve_selected"
          class="btn btn-primary btn-sm"
        >
          <.icon name="hero-check" class="size-4 mr-1" />
          {gettext("Approve selected (%{count})", count: MapSet.size(@selected))}
        </button>
        <button
          phx-click="approve_all_pending"
          data-confirm={gettext("Approve all photos awaiting review?")}
          class="btn btn-outline btn-sm"
        >
          {gettext("Approve all")}
        </button>
      </div>
    </div>

    <%!-- Photo grid --%>
    <div :if={@photos != []} class="mt-2">
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={photo <- @photos}
          id={"photo-#{photo.id}"}
          class={[
            "rounded-xl border bg-base-100 shadow-sm overflow-hidden",
            if(photo.status == :pending,
              do: "border-warning/50",
              else: "border-base-300"
            )
          ]}
        >
          <%!-- Thumbnail --%>
          <div class="relative aspect-[4/3] bg-base-200">
            <img
              src={Photos.display_url(photo)}
              alt={photo.original_filename}
              class={[
                "w-full h-full object-cover",
                photo.status == :rejected && "opacity-50 grayscale"
              ]}
              loading="lazy"
            />
            <span
              :if={photo.status != :approved}
              class={[
                "absolute top-2 left-2 text-xs font-medium px-2 py-0.5 rounded-full",
                photo.status == :pending && "bg-warning text-warning-content",
                photo.status == :rejected && "bg-error text-error-content"
              ]}
            >
              {status_label(photo.status)}
            </span>
            <label
              :if={photo.status == :pending}
              class="absolute top-2 right-2 flex items-center justify-center w-7 h-7 rounded-md bg-base-100/90 cursor-pointer"
            >
              <input
                type="checkbox"
                class="checkbox checkbox-xs"
                checked={MapSet.member?(@selected, photo.id)}
                phx-click="toggle_selected"
                phx-value-id={photo.id}
              />
            </label>
            <div
              :if={photo.bib_numbers != []}
              class="absolute bottom-2 left-2 flex flex-wrap gap-1"
            >
              <span
                :for={bib <- photo.bib_numbers}
                class="bg-black/70 text-white text-xs font-mono px-1.5 py-0.5 rounded"
              >
                #{bib}
              </span>
            </div>
          </div>

          <%!-- Details / Tagging --%>
          <div class="p-3">
            <p class="text-xs text-base-content/40 truncate">
              {photo.original_filename}
            </p>
            <p :if={photo.uploaded_by} class="text-xs text-base-content/50 truncate mt-0.5">
              <.icon name="hero-user" class="size-3 inline align-[-1px]" />
              {gettext("Submitted by %{email}", email: photo.uploaded_by.email)}
              <span class="text-base-content/30">
                · {format_date_short(photo.inserted_at)}
              </span>
            </p>
            <p :if={photo.caption} class="text-xs text-base-content/60 mt-1 line-clamp-2">
              {photo.caption}
            </p>
            <p
              :if={photo.status == :rejected && photo.rejection_reason}
              class="text-xs text-error mt-1"
            >
              {gettext("Reason:")} {photo.rejection_reason}
            </p>

            <%!-- Review actions --%>
            <div :if={photo.status == :pending} class="mt-2">
              <form
                :if={@rejecting_photo_id == photo.id}
                phx-submit="reject_photo"
                phx-value-id={photo.id}
                class="space-y-2"
              >
                <input
                  type="text"
                  name="reason"
                  maxlength="500"
                  placeholder={gettext("Optional reason shown to the uploader")}
                  class="input input-sm input-bordered w-full"
                />
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-error btn-xs">
                    {gettext("Reject")}
                  </button>
                  <button type="button" phx-click="cancel_reject" class="btn btn-ghost btn-xs">
                    {gettext("Cancel")}
                  </button>
                </div>
              </form>

              <div :if={@rejecting_photo_id != photo.id} class="flex items-center gap-1.5">
                <button
                  phx-click="approve_photo"
                  phx-value-id={photo.id}
                  class="btn btn-primary btn-xs"
                >
                  <.icon name="hero-check" class="size-3.5" />
                  {gettext("Approve")}
                </button>
                <button
                  phx-click="start_reject"
                  phx-value-id={photo.id}
                  class="btn btn-ghost btn-xs text-base-content/50 hover:text-error"
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                  {gettext("Reject")}
                </button>
              </div>
            </div>

            <div :if={photo.status == :rejected} class="mt-2">
              <button
                phx-click="approve_photo"
                phx-value-id={photo.id}
                class="btn btn-ghost btn-xs text-base-content/50 hover:text-primary"
              >
                <.icon name="hero-arrow-uturn-left" class="size-3.5" />
                {gettext("Publish anyway")}
              </button>
            </div>

            <%= if @editing_photo_id == photo.id do %>
              <form phx-submit="save_tags" phx-value-id={photo.id} class="space-y-2 mt-2">
                <div>
                  <label class="text-xs font-medium text-base-content/60">
                    {gettext("Bib Numbers")}
                  </label>
                  <input
                    type="text"
                    name="bib_numbers"
                    value={Enum.join(photo.bib_numbers || [], ", ")}
                    placeholder={gettext("e.g. 101, 203, 45")}
                    class="input input-sm input-bordered w-full mt-0.5"
                  />
                </div>
                <div>
                  <label class="text-xs font-medium text-base-content/60">
                    {gettext("Caption")}
                  </label>
                  <input
                    type="text"
                    name="caption"
                    value={photo.caption || ""}
                    placeholder={gettext("Optional caption")}
                    class="input input-sm input-bordered w-full mt-0.5"
                  />
                </div>
                <div>
                  <label class="text-xs font-medium text-base-content/60">
                    {gettext("Split")}
                  </label>
                  <select name="split_id" class="select select-sm select-bordered w-full mt-0.5">
                    <option value="">{gettext("No split")}</option>
                    <option
                      :for={split <- @splits}
                      value={split.id}
                      selected={photo.split_id == split.id}
                    >
                      {split.name}
                    </option>
                  </select>
                </div>
                <div class="flex gap-2 pt-1">
                  <button type="submit" class="btn btn-primary btn-xs">
                    {gettext("Save Tags")}
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Cancel")}
                  </button>
                </div>
              </form>
            <% else %>
              <div class="flex items-center gap-1.5 mt-1">
                <button
                  phx-click="edit_photo"
                  phx-value-id={photo.id}
                  class="btn btn-ghost btn-xs text-base-content/50 hover:text-primary"
                >
                  <.icon name="hero-tag" class="size-3.5" />
                  {gettext("Tag")}
                </button>
                <button
                  phx-click="delete_photo"
                  phx-value-id={photo.id}
                  data-confirm={gettext("Delete this photo?")}
                  class="btn btn-ghost btn-xs text-base-content/50 hover:text-error"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                  {gettext("Delete")}
                </button>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>

    <%!-- Empty state --%>
    <div :if={@photos == [] && @uploads.photos.entries == []} class="text-center py-16">
      <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200 mb-4">
        <.icon name="hero-photo" class="size-8 text-base-content/30" />
      </div>
      <p class="text-lg font-medium text-base-content/50 mb-1">{empty_title(@filter)}</p>
      <p class="text-sm text-base-content/40">
        {gettext("Upload race photos and tag them with bib numbers.")}
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("validate_uploads", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  @impl true
  def handle_event("save_uploads", _params, socket) do
    race = socket.assigns.race
    user = socket.assigns.current_scope.user

    results =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        # Organizer uploads publish immediately — no self-review.
        {:ok,
         Photos.store_upload(race.id, entry, path, %{
           status: :approved,
           uploaded_by_user_id: user.id
         })}
      end)

    {ok, failed} = Enum.split_with(results, &match?({:ok, _}, &1))
    count = length(ok)

    if count > 0 do
      AuditLog.log(user, "photos.uploaded", "race", race.id, %{"count" => count})
    end

    socket = refresh(socket)

    socket =
      cond do
        failed != [] && count == 0 ->
          put_flash(socket, :error, gettext("No photos could be uploaded."))

        failed != [] ->
          socket
          |> put_flash(
            :info,
            ngettext("%{count} photo uploaded.", "%{count} photos uploaded.", count)
          )
          |> put_flash(
            :error,
            ngettext(
              "%{count} file was skipped — not a recognised image.",
              "%{count} files were skipped — not recognised images.",
              length(failed)
            )
          )

        true ->
          put_flash(
            socket,
            :info,
            ngettext("%{count} photo uploaded.", "%{count} photos uploaded.", count)
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("approve_photo", %{"id" => id}, socket) do
    photo = Photos.get_photo!(id)

    case Photos.approve_photo(photo, socket.assigns.current_scope.user) do
      {:ok, _photo} ->
        {:noreply,
         socket
         |> deselect(photo.id)
         |> refresh()
         |> put_flash(:info, gettext("Photo approved and published."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not approve that photo."))}
    end
  end

  @impl true
  def handle_event("start_reject", %{"id" => id}, socket) do
    {:noreply, assign(socket, rejecting_photo_id: to_id(id))}
  end

  @impl true
  def handle_event("cancel_reject", _params, socket) do
    {:noreply, assign(socket, rejecting_photo_id: nil)}
  end

  @impl true
  def handle_event("reject_photo", %{"id" => id} = params, socket) do
    photo = Photos.get_photo!(id)

    case Photos.reject_photo(photo, socket.assigns.current_scope.user, params["reason"]) do
      {:ok, _photo} ->
        {:noreply,
         socket
         |> assign(rejecting_photo_id: nil)
         |> deselect(photo.id)
         |> refresh()
         |> put_flash(:info, gettext("Photo rejected."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not reject that photo."))}
    end
  end

  @impl true
  def handle_event("toggle_selected", %{"id" => id}, socket) do
    id = to_id(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply, assign(socket, selected: selected)}
  end

  @impl true
  def handle_event("approve_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected)
    count = Photos.approve_photos(ids, socket.assigns.current_scope.user)

    {:noreply,
     socket
     |> assign(selected: MapSet.new())
     |> refresh()
     |> put_flash(
       :info,
       ngettext("%{count} photo approved.", "%{count} photos approved.", count)
     )}
  end

  @impl true
  def handle_event("approve_all_pending", _params, socket) do
    ids =
      socket.assigns.race.id
      |> Photos.list_pending_photos()
      |> Enum.map(& &1.id)

    count = Photos.approve_photos(ids, socket.assigns.current_scope.user)

    {:noreply,
     socket
     |> assign(selected: MapSet.new())
     |> refresh()
     |> put_flash(
       :info,
       ngettext("%{count} photo approved.", "%{count} photos approved.", count)
     )}
  end

  @impl true
  def handle_event("edit_photo", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_photo_id: to_id(id))}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_photo_id: nil)}
  end

  @impl true
  def handle_event("save_tags", %{"id" => id} = params, socket) do
    photo = Photos.get_photo!(id)
    user = socket.assigns.current_scope.user

    bib_numbers =
      (params["bib_numbers"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    split_id =
      case params["split_id"] do
        "" -> nil
        nil -> nil
        val -> String.to_integer(val)
      end

    attrs = %{
      bib_numbers: bib_numbers,
      caption: params["caption"],
      split_id: split_id
    }

    case Photos.tag_photo(photo, attrs) do
      {:ok, _photo} ->
        AuditLog.log(user, "photo.tagged", "race_photo", photo.id, %{
          "bib_numbers" => bib_numbers
        })

        {:noreply,
         socket
         |> assign(editing_photo_id: nil)
         |> refresh()
         |> put_flash(:info, gettext("Photo tags saved."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save tags."))}
    end
  end

  @impl true
  def handle_event("delete_photo", %{"id" => id}, socket) do
    photo = Photos.get_photo!(id)
    user = socket.assigns.current_scope.user

    case Photos.delete_photo(photo) do
      {:ok, _} ->
        AuditLog.log(user, "photo.deleted", "race_photo", photo.id, %{
          "filename" => photo.original_filename
        })

        {:noreply,
         socket
         |> deselect(photo.id)
         |> refresh()
         |> put_flash(:info, gettext("Photo deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete photo."))}
    end
  end

  # phx-value ids arrive as strings from the browser.
  defp to_id(id) when is_integer(id), do: id
  defp to_id(id) when is_binary(id), do: String.to_integer(id)

  defp deselect(socket, id) do
    assign(socket, selected: MapSet.delete(socket.assigns.selected, id))
  end

  defp filter_tabs(pending_count) do
    pending_label =
      if pending_count > 0 do
        gettext("Pending (%{count})", count: pending_count)
      else
        gettext("Pending")
      end

    [
      {"pending", pending_label},
      {"approved", gettext("Published")},
      {"rejected", gettext("Rejected")},
      {"all", gettext("All")}
    ]
  end

  defp status_label(:pending), do: gettext("Pending review")
  defp status_label(:rejected), do: gettext("Rejected")
  defp status_label(_), do: gettext("Published")

  defp empty_title("pending"), do: gettext("Nothing awaiting review")
  defp empty_title("rejected"), do: gettext("No rejected photos")
  defp empty_title(_), do: gettext("No photos yet")

  defp upload_error_message(:too_large), do: gettext("File is too large (max 10MB)")
  defp upload_error_message(:too_many_files), do: gettext("Too many files (max 20)")
  defp upload_error_message(:not_accepted), do: gettext("Invalid file type")
  defp upload_error_message(_), do: gettext("Upload error")
end
