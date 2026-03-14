defmodule BibtimeWeb.Admin.ParticipantLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants

  @impl true
  def mount(%{"id" => race_id, "participant_id" => participant_id}, _session, socket) do
    race = Races.get_race!(race_id)
    participant = Participants.get_participant!(participant_id)
    changeset = Participants.change_participant(participant)
    category_options = Enum.map(race.categories, fn c -> {c.name, c.id} end)

    {:ok,
     socket
     |> assign(:race, race)
     |> assign(:participant, participant)
     |> assign(:category_options, category_options)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"participant" => participant_params}, socket) do
    changeset =
      socket.assigns.participant
      |> Participants.change_participant(participant_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"participant" => participant_params}, socket) do
    case Participants.update_participant(socket.assigns.participant, participant_params) do
      {:ok, _participant} ->
        {:noreply,
         socket
         |> put_flash(:info, "Participant updated successfully.")
         |> push_navigate(to: ~p"/admin/races/#{socket.assigns.race.id}/participants")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Edit Participant
      <:subtitle>
        <.link
          navigate={~p"/admin/races/#{@race.id}/participants"}
          class="link link-primary text-sm"
        >
          Back to participants
        </.link>
      </:subtitle>
    </.header>

    <.form for={@form} phx-change="validate" phx-submit="save" class="max-w-xl">
      <.input field={@form[:bib_number]} type="text" label="Bib Number" />
      <.input field={@form[:first_name]} type="text" label="First Name" />
      <.input field={@form[:last_name]} type="text" label="Last Name" />
      <.input field={@form[:email]} type="email" label="Email" />
      <.input field={@form[:birth_date]} type="date" label="Birth Date" />
      <.input
        field={@form[:gender]}
        type="select"
        label="Gender"
        prompt="Select gender"
        options={[Male: :male, Female: :female, Other: :other]}
      />
      <.input field={@form[:club]} type="text" label="Club" />
      <.input field={@form[:chip_id]} type="text" label="Chip ID" />
      <.input
        field={@form[:race_category_id]}
        type="select"
        label="Category"
        prompt="Select category"
        options={@category_options}
      />
      <.input
        field={@form[:status]}
        type="select"
        label="Status"
        options={[
          Registered: :registered,
          DNS: :dns,
          DNF: :dnf,
          DSQ: :dsq,
          Finished: :finished
        ]}
      />

      <div class="mt-4 flex gap-4">
        <.button type="submit" variant="primary">Update Participant</.button>
        <.button navigate={~p"/admin/races/#{@race.id}/participants"}>Cancel</.button>
      </div>
    </.form>
    """
  end
end
