defmodule BibtimeWeb.Public.RegistrationLive.New do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Registration
  alias Bibtime.Participants.Participant

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload(:categories)

    if Registration.registration_open?(race) do
      changeset = Registration.change_registration(%Participant{})

      {:ok,
       assign(socket,
         race: race,
         form: to_form(changeset),
         page_title: "Register — #{race.name}"
       )}
    else
      {:ok,
       assign(socket,
         race: race,
         form: nil,
         page_title: "Registration — #{race.name}"
       )}
    end
  end

  @impl true
  def handle_event("validate", %{"participant" => params}, socket) do
    changeset =
      %Participant{}
      |> Registration.change_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"participant" => params}, socket) do
    race = socket.assigns.race

    case Registration.register_participant(race, params) do
      {:ok, participant} ->
        {:noreply,
         socket
         |> put_flash(:info, "You're registered!")
         |> push_navigate(to: ~p"/races/#{race.slug}/register/confirmation/#{participant.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-10">
      <%!-- Back link --%>
      <.link
        navigate={~p"/races/#{@race.slug}"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/50 hover:text-base-content transition-colors mb-6"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Back to race
      </.link>

      <%!-- Header --%>
      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-base-content mb-2">
          Register for {@race.name}
        </h1>
        <p :if={@race.date} class="text-base-content/50">
          {Calendar.strftime(@race.date, "%B %d, %Y")}
          {if @race.location, do: " — #{@race.location}", else: ""}
        </p>
      </div>

      <%!-- Registration closed message --%>
      <div
        :if={@form == nil}
        class="rounded-xl bg-base-200/60 border border-base-300/50 px-8 py-12 text-center"
      >
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-300/50 mb-4">
          <.icon name="hero-lock-closed" class="size-8 text-base-content/30" />
        </div>
        <h2 class="text-xl font-semibold text-base-content mb-2">
          <%= cond do %>
            <% @race.status == :draft -> %>
              Registration is not yet open
            <% @race.status in [:in_progress, :finished] -> %>
              This race has already started
            <% true -> %>
              Registration is closed
          <% end %>
        </h2>
        <p class="text-base-content/50 mb-6">
          Check back later or view the results page for updates.
        </p>
        <.link
          navigate={~p"/races/#{@race.slug}"}
          class="btn btn-outline btn-primary"
        >
          Back to race page
        </.link>
      </div>

      <%!-- Registration form --%>
      <div :if={@form != nil} class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm">
        <.form
          for={@form}
          id="registration-form"
          phx-change="validate"
          phx-submit="save"
          class="p-6 sm:p-8 space-y-6"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <.input field={@form[:first_name]} type="text" label="First Name" required />
            <.input field={@form[:last_name]} type="text" label="Last Name" required />
          </div>

          <.input field={@form[:email]} type="email" label="Email" required />

          <.input
            field={@form[:race_category_id]}
            type="select"
            label="Category"
            prompt="Select a category"
            options={Enum.map(@race.categories, &{&1.name, &1.id})}
            required
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <.input
              field={@form[:gender]}
              type="select"
              label="Gender"
              prompt="(optional)"
              options={[{"Male", :male}, {"Female", :female}, {"Other", :other}]}
            />
            <.input field={@form[:birth_date]} type="date" label="Birth Date" />
          </div>

          <.input field={@form[:club]} type="text" label="Club / Team" placeholder="(optional)" />

          <div class="pt-4 border-t border-base-300/30">
            <button
              type="submit"
              class="btn btn-primary btn-lg w-full gap-2 shadow-md hover:shadow-lg transition-shadow"
            >
              <.icon name="hero-check-circle" class="size-5" /> Complete Registration
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
