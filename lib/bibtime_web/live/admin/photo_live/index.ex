defmodule BibtimeWeb.Admin.PhotoLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Photos
  alias Bibtime.AuditLog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    photos = Photos.list_photos(race.id)
    splits = Races.list_splits(race.id)

    {:ok,
     socket
     |> assign(
       race: race,
       photos: photos,
       splits: splits,
       page_title: gettext("Photos") <> " — " <> race.name,
       editing_photo_id: nil
     )
     |> allow_upload(:photos,
       accept: ~w(.jpg .jpeg .png .webp .gif),
       max_entries: 20,
       max_file_size: 10_000_000
     )}
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
          {ngettext("%{count} photo uploaded", "%{count} photos uploaded", length(@photos))}
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

    <%!-- Photo grid --%>
    <div :if={@photos != []} class="mt-2">
      <h2 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-4">
        {gettext("Uploaded Photos")}
      </h2>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={photo <- @photos}
          id={"photo-#{photo.id}"}
          class="rounded-xl border border-base-300 bg-base-100 shadow-sm overflow-hidden"
        >
          <%!-- Thumbnail --%>
          <div class="relative aspect-[4/3] bg-base-200">
            <img
              src={Bibtime.Photos.display_url(photo)}
              alt={photo.original_filename}
              class="w-full h-full object-cover"
              loading="lazy"
            />
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
            <p class="text-xs text-base-content/40 truncate mb-2">
              {photo.original_filename}
            </p>

            <%= if @editing_photo_id == photo.id do %>
              <form phx-submit="save_tags" phx-value-id={photo.id} class="space-y-2">
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
              <div class="flex items-center gap-1.5">
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
      <p class="text-lg font-medium text-base-content/50 mb-1">{gettext("No photos yet")}</p>
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

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        case Photos.store_upload(race.id, entry, path) do
          {:ok, photo} -> {:ok, photo}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    count = length(uploaded)

    if count > 0 do
      AuditLog.log(user, "photos.uploaded", "race", race.id, %{"count" => count})
    end

    photos = Photos.list_photos(race.id)

    {:noreply,
     socket
     |> assign(photos: photos)
     |> put_flash(:info, ngettext("%{count} photo uploaded.", "%{count} photos uploaded.", count))}
  end

  @impl true
  def handle_event("edit_photo", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_photo_id: String.to_integer(id))}
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

        photos = Photos.list_photos(socket.assigns.race.id)

        {:noreply,
         socket
         |> assign(photos: photos, editing_photo_id: nil)
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

        photos = Photos.list_photos(socket.assigns.race.id)

        {:noreply,
         socket
         |> assign(photos: photos)
         |> put_flash(:info, gettext("Photo deleted."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete photo."))}
    end
  end

  defp upload_error_message(:too_large), do: gettext("File is too large (max 10MB)")
  defp upload_error_message(:too_many_files), do: gettext("Too many files (max 20)")
  defp upload_error_message(:not_accepted), do: gettext("Invalid file type")
  defp upload_error_message(_), do: gettext("Upload error")
end
