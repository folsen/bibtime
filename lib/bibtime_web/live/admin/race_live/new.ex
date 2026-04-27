defmodule BibtimeWeb.Admin.RaceLive.New do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Races.Race
  alias Bibtime.Races.Templates
  alias Bibtime.AuditLog

  @impl true
  def mount(_params, _session, socket) do
    changeset = Races.change_race(%Race{}, %{status: :draft})
    existing_races = Races.list_races()

    {:ok,
     socket
     |> assign(:page_title, gettext("New Race"))
     |> assign(:selected_template, "")
     |> assign(:clone_from, "")
     |> assign(:existing_races, existing_races)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    clone_from = params["clone_from"] || ""

    socket =
      if clone_from != "" do
        source = Races.get_race!(clone_from)

        changeset =
          Races.change_race(%Race{}, %{
            status: :draft,
            race_type: source.race_type
          })

        socket
        |> assign(:clone_from, clone_from)
        |> assign(:selected_template, "")
        |> assign_form(changeset)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-6">
      <h1 class="text-2xl font-semibold tracking-tight text-base-content">{gettext("New Race")}</h1>
      <p class="mt-1 text-sm text-base-content/60">
        {gettext("Fill in the details to create a new race event.")}
      </p>
    </div>

    <div class="max-w-2xl">
      <%!-- Quick Start --%>
      <div class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm mb-6">
        <h3 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-4">
          {gettext("Quick Start")}
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <form phx-change="select_template">
            <label class="block text-sm font-medium text-base-content mb-1.5">
              {gettext("From Template")}
            </label>
            <select
              name="template"
              class="select select-bordered w-full"
            >
              {Phoenix.HTML.Form.options_for_select(
                Templates.options_for_select(),
                @selected_template
              )}
            </select>
          </form>
          <form phx-change="select_clone">
            <label class="block text-sm font-medium text-base-content mb-1.5">
              {gettext("Clone from Race")}
            </label>
            <select
              name="clone_from"
              class="select select-bordered w-full"
            >
              {Phoenix.HTML.Form.options_for_select(
                [{gettext("Don't clone"), ""}] ++
                  Enum.map(@existing_races, fn r -> {r.name, r.id} end),
                @clone_from
              )}
            </select>
          </form>
        </div>
        <p
          :if={@selected_template != "" || @clone_from != ""}
          class="mt-3 text-xs text-info flex items-center gap-1"
        >
          <.icon name="hero-information-circle" class="size-3.5" />
          {gettext("Splits and categories will be auto-created from the selected source.")}
        </p>
      </div>

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

          <%!-- Registration Settings --%>
          <div class="pt-4 border-t border-base-200">
            <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider mb-4">
              {gettext("Registration Settings")}
            </h3>

            <div class="space-y-4">
              <div>
                <.input
                  field={@form[:participant_limit]}
                  type="number"
                  label={gettext("Participant limit")}
                  placeholder={gettext("Unlimited")}
                  min="1"
                />
                <p class="text-xs text-base-content/40 mt-1">
                  {gettext("Leave empty for unlimited registrations")}
                </p>
              </div>
            </div>
          </div>

          <%!-- Photo Settings --%>
          <div class="pt-4 border-t border-base-200">
            <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider mb-4">
              {gettext("Photo Settings")}
            </h3>

            <div class="space-y-2">
              <.input
                field={@form[:photos_public]}
                type="checkbox"
                label={gettext("Photos visible to everyone")}
              />
              <p class="text-xs text-base-content/40">
                {gettext(
                  "When unchecked, only logged-in race participants can view photos for this race."
                )}
              </p>
            </div>
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
              <.icon name="hero-plus" class="size-4 mr-1" /> {gettext("Create Race")}
            </.button>
            <.link
              navigate={~p"/admin/races"}
              class="text-sm text-base-content/50 hover:text-base-content transition-colors"
            >
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_template", %{"template" => template_id}, socket) do
    socket =
      if template_id != "" do
        template = Templates.get(template_id)

        if template do
          changeset =
            Races.change_race(%Race{}, %{
              status: :draft,
              race_type: template.race_type
            })

          socket
          |> assign(:selected_template, template_id)
          |> assign(:clone_from, "")
          |> assign_form(changeset)
        else
          assign(socket, :selected_template, "")
        end
      else
        assign(socket, :selected_template, "")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_clone", %{"clone_from" => clone_id}, socket) do
    socket =
      if clone_id != "" do
        source = Races.get_race!(clone_id)

        changeset =
          Races.change_race(%Race{}, %{
            status: :draft,
            race_type: source.race_type
          })

        socket
        |> assign(:clone_from, clone_id)
        |> assign(:selected_template, "")
        |> assign_form(changeset)
      else
        assign(socket, :clone_from, "")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"race" => race_params}, socket) do
    race_params = maybe_generate_slug(race_params)

    changeset =
      %Race{}
      |> Races.change_race(race_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"race" => race_params}, socket) do
    result =
      cond do
        socket.assigns.selected_template != "" ->
          Races.create_race_from_template(race_params, socket.assigns.selected_template)

        socket.assigns.clone_from != "" ->
          Races.clone_race(socket.assigns.clone_from, race_params)

        true ->
          Races.create_race(race_params)
      end

    case result do
      {:ok, race} ->
        AuditLog.log(socket.assigns.current_scope.user, "race.created", "race", race.id, %{
          "name" => race.name
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Race created successfully."))
         |> push_navigate(to: ~p"/admin/races/#{race.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp maybe_generate_slug(%{"name" => name, "slug" => ""} = params) when name != "" do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    Map.put(params, "slug", slug)
  end

  defp maybe_generate_slug(%{"name" => name} = params) when is_binary(name) do
    # If slug is not present at all (first validation), generate it
    if Map.has_key?(params, "slug") do
      params
    else
      slug =
        name
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9\s-]/, "")
        |> String.replace(~r/\s+/, "-")
        |> String.trim("-")

      Map.put(params, "slug", slug)
    end
  end

  defp maybe_generate_slug(params), do: params

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
