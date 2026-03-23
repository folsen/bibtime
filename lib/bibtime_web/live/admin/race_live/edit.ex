defmodule BibtimeWeb.Admin.RaceLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.AuditLog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    changeset = Races.change_race(race)

    {:ok,
     socket
     |> assign(:page_title, gettext("Edit %{name}", name: race.name))
     |> assign(:race, race)
     |> assign_form(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-6">
      <h1 class="text-2xl font-semibold tracking-tight text-base-content">{gettext("Edit Race")}</h1>
      <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
    </div>

    <div class="max-w-2xl">
      <div class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-6">
          <%!-- Name & Slug --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:name]}
              type="text"
              label={gettext("Name")}
              required
              phx-debounce="300"
            />
            <.input
              field={@form[:slug]}
              type="text"
              label={gettext("Slug")}
              required
              phx-debounce="300"
            />
          </div>

          <%!-- Date & Location --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input field={@form[:date]} type="date" label={gettext("Date")} />
            <.input field={@form[:location]} type="text" label={gettext("Location")} />
          </div>

          <%!-- Description --%>
          <.input field={@form[:description]} type="textarea" label={gettext("Description")} rows="4" />

          <%!-- Type & Status --%>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:race_type]}
              type="select"
              label={gettext("Race Type")}
              options={race_type_options()}
              required
            />
            <.input
              field={@form[:status]}
              type="select"
              label={gettext("Status")}
              options={status_options()}
              required
            />
          </div>

          <%!-- Payment Settings --%>
          <div class="pt-4 border-t border-base-200">
            <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider mb-4">
              {gettext("Payment Settings")}
            </h3>

            <div class="space-y-4">
              <.input
                field={@form[:payment_required]}
                type="checkbox"
                label={gettext("Require payment for registration")}
              />

              <div
                :if={Phoenix.HTML.Form.input_value(@form, :payment_required) in [true, "true"]}
                class="ml-6 space-y-4 pl-4 border-l-2 border-primary/20"
              >
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <.input
                      field={@form[:entry_fee_cents]}
                      type="number"
                      label={gettext("Entry fee (in smallest currency unit)")}
                      placeholder="30000"
                      min="1"
                      required
                    />
                    <p class="text-xs text-base-content/40 mt-1">
                      {gettext("E.g. 30000 = 300.00 SEK")}
                    </p>
                  </div>
                  <.input
                    field={@form[:currency]}
                    type="select"
                    label={gettext("Currency")}
                    options={currency_options()}
                  />
                </div>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <.input
                      field={@form[:early_bird_fee_cents]}
                      type="number"
                      label={gettext("Early bird fee (optional)")}
                      placeholder="25000"
                      min="1"
                    />
                    <p class="text-xs text-base-content/40 mt-1">
                      {gettext("Leave empty for no early bird pricing")}
                    </p>
                  </div>
                  <.input
                    field={@form[:early_bird_deadline]}
                    type="date"
                    label={gettext("Early bird deadline")}
                  />
                </div>
              </div>
            </div>
          </div>

          <%!-- Actions --%>
          <div class="flex items-center gap-4 pt-4 border-t border-base-200">
            <.button type="submit" variant="primary">
              <.icon name="hero-check" class="size-4 mr-1" /> {gettext("Save Changes")}
            </.button>
            <.link
              navigate={~p"/admin/races/#{@race.id}"}
              class="text-sm text-base-content/50 hover:text-base-content transition-colors"
            >
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>
      </div>
    </div>

    <div class="mt-8 pt-4 border-t border-base-200">
      <.link
        navigate={~p"/admin/races/#{@race.id}"}
        class="text-sm text-base-content/50 hover:text-primary transition-colors flex items-center gap-1"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> {gettext("Back to race")}
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
        AuditLog.log(socket.assigns.current_scope.user, "race.updated", "race", race.id, %{
          "name" => race.name
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Race updated successfully."))
         |> push_navigate(to: ~p"/admin/races/#{race.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
