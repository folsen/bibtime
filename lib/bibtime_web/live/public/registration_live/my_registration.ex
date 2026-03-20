defmodule BibtimeWeb.Public.RegistrationLive.MyRegistration do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Results
  alias Bibtime.Results.Calculator

  @impl true
  def mount(%{"slug" => slug, "token" => token}, _session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :splits])

    participant = Participants.get_participant_by_token(token)

    if participant && participant.race_id == race.id do
      splits = Races.list_splits(race.id)

      result =
        if race.status in [:in_progress, :finished] do
          race.id
          |> Results.get_race_results()
          |> Enum.find(&(&1.participant.id == participant.id))
        end

      if connected?(socket) && race.status == :in_progress do
        Phoenix.PubSub.subscribe(Bibtime.PubSub, "race:timing:#{race.id}")
      end

      {:ok,
       assign(socket,
         race: race,
         participant: participant,
         splits: splits,
         result: result,
         page_title: "My Registration — #{race.name}"
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Registration not found")
       |> push_navigate(to: ~p"/races/#{slug}")}
    end
  end

  @impl true
  def handle_info({:split_time_recorded, _}, socket) do
    {:noreply, recalculate_result(socket)}
  end

  @impl true
  def handle_info({:split_time_deleted, _}, socket) do
    {:noreply, recalculate_result(socket)}
  end

  defp recalculate_result(socket) do
    race = socket.assigns.race
    participant = socket.assigns.participant

    result =
      race.id
      |> Results.get_race_results()
      |> Enum.find(&(&1.participant.id == participant.id))

    assign(socket, result: result)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-10">
      <.link
        navigate={~p"/races/#{@race.slug}"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/50 hover:text-base-content transition-colors mb-6"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Back to race
      </.link>

      <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden">
        <%!-- Header --%>
        <div class="px-8 py-6 border-b border-base-300/30">
          <div class="flex items-center gap-4">
            <div class="flex items-center justify-center w-14 h-14 rounded-2xl bg-primary/10 border border-primary/20">
              <span class="text-2xl font-bold font-mono text-primary">{@participant.bib_number}</span>
            </div>
            <div>
              <h1 class="text-xl font-bold text-base-content">
                {@participant.first_name} {@participant.last_name}
              </h1>
              <p class="text-sm text-base-content/50">
                {@race.name}
                <span :if={@participant.race_category}>
                  — {@participant.race_category.name}
                </span>
              </p>
            </div>
            <span class={[
              "ml-auto inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold",
              status_class(@participant.status)
            ]}>
              {format_status(@participant.status)}
            </span>
          </div>
        </div>

        <%!-- Details --%>
        <div class="px-8 py-5">
          <div class="divide-y divide-base-300/30">
            <div :if={@participant.email} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Email</span>
              <span class="text-sm text-base-content">{@participant.email}</span>
            </div>
            <div :if={@participant.club} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Club</span>
              <span class="text-sm text-base-content">{@participant.club}</span>
            </div>
            <div :if={@participant.gender} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">Gender</span>
              <span class="text-sm text-base-content capitalize">{@participant.gender}</span>
            </div>
          </div>
        </div>

        <%!-- Split times (during/after race) --%>
        <div :if={@result} class="px-8 py-5 border-t border-base-300/30">
          <h2 class="text-sm uppercase tracking-wide text-base-content/50 font-semibold mb-4">
            Split Times
          </h2>

          <div class="space-y-2">
            <div
              :for={split <- @splits}
              class="flex items-center justify-between rounded-lg bg-base-200/40 px-4 py-2.5"
            >
              <span class="text-sm text-base-content/70">{split.name}</span>
              <span class="font-mono text-sm font-medium text-base-content">
                {Calculator.format_time(Map.get(@result.leg_times, split.id))}
              </span>
            </div>
          </div>

          <div
            :if={@result.total_ms}
            class="mt-4 flex items-center justify-between rounded-lg bg-primary/8 border border-primary/20 px-4 py-3"
          >
            <span class="text-sm font-semibold text-primary/80">Total Time</span>
            <span class="font-mono text-lg font-bold text-primary">
              {Calculator.format_time(@result.total_ms)}
            </span>
          </div>

          <div :if={@result.rank} class="mt-3 text-center">
            <span class="text-sm text-base-content/50">Overall rank: </span>
            <span class="font-mono font-bold text-base-content">{@result.rank}</span>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="px-8 py-5 bg-base-200/30 border-t border-base-300/30 flex flex-wrap gap-3">
          <.link
            navigate={~p"/races/#{@race.slug}/results"}
            class="btn btn-outline btn-primary btn-sm gap-1.5"
          >
            <.icon name="hero-trophy" class="size-4" /> Full Results
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp status_class(:registered), do: "bg-base-content/10 text-base-content/60"
  defp status_class(:racing), do: "bg-info/15 text-info"
  defp status_class(:finished), do: "bg-success/15 text-success"
  defp status_class(:dns), do: "bg-warning/15 text-warning"
  defp status_class(:dnf), do: "bg-error/15 text-error"
  defp status_class(:dsq), do: "bg-error/15 text-error"
  defp status_class(_), do: "bg-base-content/10 text-base-content/60"

  defp format_status(:dns), do: "DNS"
  defp format_status(:dnf), do: "DNF"
  defp format_status(:dsq), do: "DSQ"

  defp format_status(status) do
    status |> Atom.to_string() |> String.capitalize()
  end
end
