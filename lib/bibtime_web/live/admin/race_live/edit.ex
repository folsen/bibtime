defmodule BibtimeWeb.Admin.RaceLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.Races

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    changeset = Races.change_race(race)

    {:ok,
     socket
     |> assign(:page_title, "Edit #{race.name}")
     |> assign(:race, race)
     |> assign_form(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-6">
      <h1 class="text-2xl font-semibold tracking-tight text-base-content">Edit Race</h1>
      <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
    </div>

    <div class="max-w-2xl">
      <div class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
          <%!-- Name & Slug --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Name" required phx-debounce="300" />
            <.input field={@form[:slug]} type="text" label="Slug" required phx-debounce="300" />
          </div>

          <%!-- Date & Location --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:date]} type="date" label="Date" />
            <.input field={@form[:location]} type="text" label="Location" />
          </div>

          <%!-- Description --%>
          <.input field={@form[:description]} type="textarea" label="Description" rows="4" />

          <%!-- Type & Status --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:race_type]}
              type="select"
              label="Race Type"
              options={race_type_options()}
              required
            />
            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              options={status_options()}
              required
            />
          </div>

          <%!-- Actions --%>
          <div class="flex items-center gap-4 pt-4 border-t border-base-200">
            <.button type="submit" variant="primary">
              <.icon name="hero-check" class="size-4 mr-1" /> Save Changes
            </.button>
            <.link navigate={~p"/admin/races/#{@race.id}"} class="text-sm text-base-content/50 hover:text-base-content transition-colors">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </div>

    <div class="mt-8 pt-4 border-t border-base-200">
      <.link navigate={~p"/admin/races/#{@race.id}"} class="text-sm text-base-content/50 hover:text-primary transition-colors flex items-center gap-1">
        <.icon name="hero-arrow-left" class="size-3.5" /> Back to race
      </.link>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"race" => race_params}, socket) do
    changeset =
      socket.assigns.race
      |> Races.change_race(race_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"race" => race_params}, socket) do
    case Races.update_race(socket.assigns.race, race_params) do
      {:ok, race} ->
        {:noreply,
         socket
         |> put_flash(:info, "Race updated successfully.")
         |> push_navigate(to: ~p"/admin/races/#{race.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp race_type_options do
    [
      {"Triathlon", :triathlon},
      {"Running", :running},
      {"Cycling", :cycling},
      {"Swimming", :swimming},
      {"Custom", :custom}
    ]
  end

  defp status_options do
    [
      {"Draft", :draft},
      {"Registration Open", :registration_open},
      {"Registration Closed", :registration_closed},
      {"In Progress", :in_progress},
      {"Finished", :finished},
      {"Archived", :archived}
    ]
  end
end
