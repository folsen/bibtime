defmodule BibtimeWeb.Admin.ParticipantLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.AuditLog

  @impl true
  def mount(%{"id" => race_id, "participant_id" => participant_id}, _session, socket) do
    race = Races.get_race!(race_id, preload: [:categories])

    participant =
      Participants.get_participant!(participant_id) |> Bibtime.Repo.preload(:user)

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
      {:ok, participant} ->
        AuditLog.log(
          socket.assigns.current_scope.user,
          "participant.updated",
          "participant",
          participant.id,
          %{"bib" => participant.bib_number, "race_id" => socket.assigns.race.id}
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Participant updated successfully."))
         |> push_navigate(to: ~p"/admin/races/#{socket.assigns.race.id}/participants")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {gettext("Edit Participant")}
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

      <%!-- Email is read-only here. It lives on the user account, not the
            participant — to change it, the user updates it via account
            settings (or an admin can edit via the user admin screen). --%>
      <div :if={@participant.user} class="form-control mb-3">
        <label class="label">
          <span class="label-text">{gettext("Email")}</span>
        </label>
        <div class="text-sm text-base-content/70 px-3 py-2 bg-base-200/40 rounded">
          {@participant.user.email}
        </div>
      </div>

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
        :if={@race.categories != []}
        field={@form[:race_category_id]}
        type="select"
        label={gettext("Category")}
        prompt={gettext("Select category")}
        options={@category_options}
      />
      <.input
        field={@form[:status]}
        type="select"
        label={gettext("Status")}
        options={[
          {gettext("Registered"), :registered},
          {"DNS", :dns},
          {"DNF", :dnf},
          {"DSQ", :dsq},
          {gettext("Finished"), :finished}
        ]}
      />

      <div class="mt-4 flex gap-4">
        <.button type="submit" variant="primary">{gettext("Update Participant")}</.button>
        <.button navigate={~p"/admin/races/#{@race.id}/participants"}>{gettext("Cancel")}</.button>
      </div>
    </.form>
    """
  end
end
