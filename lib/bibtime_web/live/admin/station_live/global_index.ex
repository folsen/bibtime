defmodule BibtimeWeb.Admin.StationLive.GlobalIndex do
  use BibtimeWeb, :live_view

  alias Bibtime.Timing
  alias Bibtime.Timing.TimingStation

  @impl true
  def mount(_params, _session, socket) do
    stations = Timing.list_all_stations()

    form =
      %TimingStation{}
      |> TimingStation.changeset(%{})
      |> to_form(as: "station")

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:token_mode, :generate)
     |> assign(:new_station, nil)
     |> stream(:stations, stations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="pb-6">
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Timing Stations")}
        </h1>
        <p class="mt-1 text-sm text-base-content/60">
          {gettext(
            "Manage physical timing stations. Assign them to race splits from each race's station page."
          )}
        </p>
      </div>

      <%!-- New-station reveal --%>
      <div
        :if={@new_station}
        class="mb-6 rounded-xl border border-warning/40 bg-warning/5 p-5 shadow-sm"
      >
        <div class="flex items-start gap-3">
          <.icon name="hero-key" class="size-5 text-warning mt-0.5" />
          <div class="flex-1">
            <h3 class="font-semibold text-base-content">
              {gettext("Station created — copy the token now")}
            </h3>
            <p class="text-sm text-base-content/60 mt-1">
              {gettext(
                "This token will not be shown again. Paste it into the station's firmware configuration."
              )}
            </p>
            <div class="mt-3 rounded-lg bg-base-100 border border-base-300 px-3 py-2 font-mono text-xs break-all select-all">
              {@new_station.token}
            </div>
            <div class="mt-3">
              <button
                phx-click="dismiss_new_station"
                class="btn btn-sm btn-ghost"
              >
                {gettext("Dismiss")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Stations list --%>
      <div class="rounded-xl border border-base-300 bg-base-100 shadow-sm overflow-hidden">
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">{gettext("Name")}</th>
              <th class="font-semibold">{gettext("Assignment")}</th>
              <th class="font-semibold">{gettext("Status")}</th>
              <th class="font-semibold">{gettext("Firmware")}</th>
              <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody id="stations" phx-update="stream">
            <tr
              :for={{dom_id, station} <- @streams.stations}
              id={dom_id}
              class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
            >
              <td class="py-3 font-medium">{station.name}</td>
              <td class="py-3 text-sm text-base-content/70">
                {assignment_label(station)}
              </td>
              <td class="py-3">
                <span class={[
                  "inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium",
                  status_badge(station.status)
                ]}>
                  <span class={["inline-block size-1.5 rounded-full", status_dot(station.status)]} />
                  {status_label(station.status)}
                </span>
              </td>
              <td class="py-3 text-xs text-base-content/60 font-mono">
                {station.firmware_version || "-"}
              </td>
              <td class="py-3 pr-4">
                <button
                  phx-click="delete"
                  phx-value-id={station.id}
                  data-confirm={gettext("Delete this station? Any race assignments will be removed.")}
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  {gettext("Delete")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Create station form --%>
      <div class="mt-6 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" />
          {gettext("Add Station")}
        </h3>

        <div class="mb-4 flex gap-2">
          <button
            phx-click="set_token_mode"
            phx-value-mode="generate"
            class={[
              "btn btn-sm",
              if(@token_mode == :generate, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {gettext("Generate token")}
          </button>
          <button
            phx-click="set_token_mode"
            phx-value-mode="manual"
            class={[
              "btn btn-sm",
              if(@token_mode == :manual, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {gettext("Enter token manually")}
          </button>
        </div>

        <.form for={@form} phx-submit="create" class="flex flex-wrap gap-3 items-end">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Name")}
            required
            placeholder={gettext("e.g. Finish Line Reader")}
          />
          <.input
            :if={@token_mode == :manual}
            field={@form[:token]}
            type="text"
            label={gettext("Token")}
            required
            placeholder={gettext("Paste the token from the station label")}
          />
          <.button type="submit" variant="primary">{gettext("Create")}</.button>
        </.form>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("create", %{"station" => params}, socket) do
    case Timing.create_timing_station(params) do
      {:ok, station} ->
        station = Bibtime.Repo.preload(station, assigned_split: :race)

        form =
          %TimingStation{}
          |> TimingStation.changeset(%{})
          |> to_form(as: "station")

        {:noreply,
         socket
         |> assign(:form, form)
         |> assign(:new_station, station)
         |> stream_insert(:stations, station)
         |> put_flash(:info, gettext("Station created."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "station"))}
    end
  end

  def handle_event("set_token_mode", %{"mode" => mode}, socket) do
    token_mode =
      case mode do
        "manual" -> :manual
        _ -> :generate
      end

    {:noreply, assign(socket, :token_mode, token_mode)}
  end

  def handle_event("dismiss_new_station", _params, socket) do
    {:noreply, assign(socket, :new_station, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    station = Timing.get_timing_station!(id)
    {:ok, _} = Timing.delete_timing_station(station)

    {:noreply,
     socket
     |> stream_delete(:stations, station)
     |> put_flash(:info, gettext("Station deleted."))}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp assignment_label(%{assigned_split: %{name: split_name, race: %{name: race_name}}}) do
    "#{race_name} — #{split_name}"
  end

  defp assignment_label(_), do: gettext("Unassigned")

  defp status_badge(:online), do: "bg-success/10 text-success"
  defp status_badge(:reading), do: "bg-info/10 text-info"
  defp status_badge(:error), do: "bg-error/10 text-error"
  defp status_badge(_), do: "bg-base-200 text-base-content/50"

  defp status_dot(:online), do: "bg-success"
  defp status_dot(:reading), do: "bg-info"
  defp status_dot(:error), do: "bg-error"
  defp status_dot(_), do: "bg-base-300"

  defp status_label(:online), do: gettext("online")
  defp status_label(:reading), do: gettext("reading")
  defp status_label(:error), do: gettext("error")
  defp status_label(:offline), do: gettext("offline")
  defp status_label(other), do: to_string(other)
end
