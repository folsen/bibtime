defmodule BibtimeWeb.Admin.ParticipantLive.New do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Participants.Participant
  alias Bibtime.AuditLog

  @impl true
  def mount(%{"id" => race_id}, _session, socket) do
    race = Races.get_race!(race_id, preload: [:categories])
    changeset = Participants.change_participant(%Participant{race_id: race.id})
    category_options = Enum.map(race.categories, fn c -> {c.name, c.id} end)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:category_options, category_options)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"participant" => participant_params}, socket) do
    changeset =
      %Participant{race_id: socket.assigns.race.id}
      |> Participants.change_participant(participant_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"participant" => participant_params}, socket) do
    participant_params = Map.put(participant_params, "race_id", socket.assigns.race.id)

    case Participants.create_participant(participant_params) do
      {:ok, participant} ->
        AuditLog.log(
          socket.assigns.current_scope.user,
          "participant.created",
          "participant",
          participant.id,
          %{"bib" => participant.bib_number, "race_id" => socket.assigns.race.id}
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Participant created successfully."))
         |> push_navigate(to: ~p"/admin/races/#{socket.assigns.race.id}/participants")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {gettext("Add Participant")}
      <:subtitle>
        <.link
          navigate={~p"/admin/races/#{@race.id}/participants"}
          class="link link-primary text-sm"
        >
          {gettext("Back to participants")}
        </.link>
      </:subtitle>
    </.header>

    <.form for={@form} phx-change="validate" phx-submit="save" class="max-w-xl">
      <.input field={@form[:bib_number]} type="text" label={gettext("Bib Number")} />
      <.input field={@form[:first_name]} type="text" label={gettext("First Name")} />
      <.input field={@form[:last_name]} type="text" label={gettext("Last Name")} />
      <.input field={@form[:email]} type="email" label={gettext("Email")} />
      <.input field={@form[:birth_date]} type="date" label={gettext("Birth Date")} />
      <.input
        field={@form[:gender]}
        type="select"
        label={gettext("Gender")}
        prompt={gettext("Select gender")}
        options={gender_options()}
      />
      <.input field={@form[:club]} type="text" label={gettext("Club")} />
      <.input field={@form[:chip_id]} type="text" label={gettext("Chip ID")} />
      <.input
        field={@form[:race_category_id]}
        type="select"
        label={gettext("Category")}
        prompt={gettext("Select category")}
        options={@category_options}
      />

      <div class="mt-4 flex gap-4">
        <.button type="submit" variant="primary">{gettext("Create Participant")}</.button>
        <.button navigate={~p"/admin/races/#{@race.id}/participants"}>{gettext("Cancel")}</.button>
      </div>
    </.form>
    """
  end
end
