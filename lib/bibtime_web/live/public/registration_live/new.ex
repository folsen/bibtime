defmodule BibtimeWeb.Public.RegistrationLive.New do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Registration
  alias Bibtime.Participants.Participant

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :auto_categories])

    if Registration.registration_open?(race) do
      has_manual_categories = race.categories != []
      auto_cat_types = race.auto_categories |> Enum.map(& &1.type) |> Enum.uniq()
      requires_gender = :gender in auto_cat_types
      requires_birth_date = :age_group in auto_cat_types

      reg_opts = [
        require_category: has_manual_categories,
        require_gender: requires_gender,
        require_birth_date: requires_birth_date
      ]

      prefill_attrs = prefill_attrs_for_user(socket.assigns.current_scope)
      changeset = Registration.change_registration(%Participant{}, prefill_attrs, reg_opts)

      {:ok,
       assign(socket,
         race: race,
         form: to_form(changeset),
         has_manual_categories: has_manual_categories,
         requires_gender: requires_gender,
         requires_birth_date: requires_birth_date,
         reg_opts: reg_opts,
         page_title: gettext("Register") <> " — " <> race.name
       )}
    else
      {:ok,
       assign(socket,
         race: race,
         form: nil,
         page_title: gettext("Registration") <> " — " <> race.name
       )}
    end
  end

  @impl true
  def handle_event("validate", %{"participant" => params}, socket) do
    changeset =
      %Participant{}
      |> Registration.change_registration(params, socket.assigns.reg_opts)
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
         |> put_flash(:info, gettext("You're registered!"))
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
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to race")}
      </.link>

      <%!-- Header --%>
      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-base-content mb-2">
          {gettext("Register for %{name}", name: @race.name)}
        </h1>
        <p :if={@race.date} class="text-base-content/50">
          {format_date(@race.date)}
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
              {gettext("Registration is not yet open")}
            <% @race.status in [:in_progress, :finished] -> %>
              {gettext("This race has already started")}
            <% true -> %>
              {gettext("Registration is closed")}
          <% end %>
        </h2>
        <p class="text-base-content/50 mb-6">
          {gettext("Check back later or view the results page for updates.")}
        </p>
        <.link
          navigate={~p"/races/#{@race.slug}"}
          class="btn btn-outline btn-primary"
        >
          {gettext("Back to race page")}
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
            <.input field={@form[:first_name]} type="text" label={gettext("First Name")} required />
            <.input field={@form[:last_name]} type="text" label={gettext("Last Name")} required />
          </div>

          <.input field={@form[:email]} type="email" label={gettext("Email")} required />

          <.input
            :if={@has_manual_categories}
            field={@form[:race_category_id]}
            type="select"
            label={gettext("Category")}
            prompt={gettext("Select a category")}
            options={Enum.map(@race.categories, &{&1.name, &1.id})}
            required
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <.input
              field={@form[:gender]}
              type="select"
              label={gettext("Gender")}
              prompt={if @requires_gender, do: gettext("Select gender"), else: gettext("(optional)")}
              options={gender_options()}
              required={@requires_gender}
            />
            <.input
              field={@form[:birth_date]}
              type="date"
              label={gettext("Birth Date")}
              required={@requires_birth_date}
            />
          </div>

          <p
            :if={@requires_gender || @requires_birth_date}
            class="text-sm text-base-content/50 -mt-2"
          >
            {gettext("You'll be automatically placed in categories based on your info.")}
          </p>

          <.input
            field={@form[:club]}
            type="text"
            label={gettext("Club / Team")}
            placeholder={gettext("(optional)")}
          />

          <div class="pt-4 border-t border-base-300/30">
            <button
              type="submit"
              class="btn btn-primary btn-lg w-full gap-2 shadow-md hover:shadow-lg transition-shadow"
            >
              <.icon name="hero-check-circle" class="size-5" /> {gettext("Complete Registration")}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp prefill_attrs_for_user(%{user: nil}), do: %{}
  defp prefill_attrs_for_user(nil), do: %{}

  defp prefill_attrs_for_user(%{user: user}) do
    case Participants.get_latest_participant_for_user(user.id) do
      %Participant{} = p ->
        %{
          "first_name" => p.first_name,
          "last_name" => p.last_name,
          "email" => p.email || user.email,
          "gender" => if(p.gender, do: Atom.to_string(p.gender)),
          "birth_date" => if(p.birth_date, do: Date.to_iso8601(p.birth_date)),
          "club" => p.club
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      nil ->
        %{"email" => user.email}
    end
  end
end
