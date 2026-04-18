defmodule BibtimeWeb.Public.MyRacesLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.Participants
  alias Bibtime.Participants.Participant

  @impl true
  def mount(%{"participant_id" => participant_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    participant =
      Participants.get_participant!(participant_id)
      |> Bibtime.Repo.preload([:race, :race_category])

    # Ensure the participant belongs to this user
    if participant.user_id != user.id do
      {:ok,
       socket
       |> put_flash(:error, gettext("Not found"))
       |> push_navigate(to: ~p"/my-races")}
    else
      race = participant.race |> Bibtime.Repo.preload(:categories)

      # Only allow editing before/during registration
      editable? = race.status in [:registration_open, :registration_closed]

      changeset = Participant.registration_changeset(participant, %{})

      {:ok,
       assign(socket,
         participant: participant,
         race: race,
         editable?: editable?,
         form: to_form(changeset),
         page_title: gettext("Edit Registration") <> " — " <> race.name
       )}
    end
  end

  @impl true
  def handle_event("validate", %{"participant" => params}, socket) do
    changeset =
      socket.assigns.participant
      |> Participant.registration_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"participant" => params}, socket) do
    participant = socket.assigns.participant

    changeset = Participant.registration_changeset(participant, params)

    case Bibtime.Repo.update(changeset) do
      {:ok, _participant} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Registration updated"))
         |> push_navigate(to: ~p"/my-races")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-10">
      <.link
        navigate={~p"/my-races"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/50 hover:text-base-content transition-colors mb-6"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        {gettext("Back to My Races")}
      </.link>

      <div class="mb-8">
        <h1 class="text-3xl font-bold tracking-tight text-base-content mb-2">
          {gettext("Edit Registration")}
        </h1>
        <p class="text-base-content/50">
          {@race.name}
          <span :if={@participant.bib_number} class="font-mono">
            — Bib #{@participant.bib_number}
          </span>
        </p>
      </div>

      <div :if={!@editable?} class="rounded-xl bg-warning/10 border border-warning/20 px-6 py-4 mb-6">
        <p class="text-sm text-warning font-medium">
          {gettext(
            "This race is already in progress. Your registration details can no longer be changed."
          )}
        </p>
      </div>

      <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm">
        <.form
          for={@form}
          id="edit-registration-form"
          phx-change="validate"
          phx-submit="save"
          class="p-6 sm:p-8 space-y-6"
        >
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <.input
              field={@form[:first_name]}
              type="text"
              label={gettext("First Name")}
              required
              disabled={!@editable?}
            />
            <.input
              field={@form[:last_name]}
              type="text"
              label={gettext("Last Name")}
              disabled={!@editable?}
            />
          </div>

          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            required
            disabled={!@editable?}
          />

          <.input
            field={@form[:race_category_id]}
            type="select"
            label={gettext("Category")}
            prompt={gettext("Select a category")}
            options={Enum.map(@race.categories, &{&1.name, &1.id})}
            required
            disabled={!@editable?}
          />

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
            <.input
              field={@form[:gender]}
              type="select"
              label={gettext("Gender")}
              prompt={gettext("(optional)")}
              options={gender_options()}
              disabled={!@editable?}
            />
            <.input
              field={@form[:birth_date]}
              type="date"
              label={gettext("Birth Date")}
              disabled={!@editable?}
            />
          </div>

          <.input
            field={@form[:club]}
            type="text"
            label={gettext("Club / Team")}
            placeholder={gettext("(optional)")}
            disabled={!@editable?}
          />

          <div :if={@editable?} class="pt-4 border-t border-base-300/30">
            <button
              type="submit"
              class="btn btn-primary btn-lg w-full gap-2 shadow-md hover:shadow-lg transition-shadow"
            >
              <.icon name="hero-check-circle" class="size-5" />
              {gettext("Save Changes")}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
