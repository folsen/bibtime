defmodule BibtimeWeb.Public.ProfileLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Participants
  alias Bibtime.Photos
  alias Bibtime.Races
  alias Bibtime.Results
  alias Bibtime.Results.Calculator

  @impl true
  def mount(%{"participant_id" => participant_id}, _session, socket) do
    user = socket.assigns.current_scope.user
    participant = Participants.get_participant!(participant_id)

    # Verify the participant belongs to the current user
    case participant.user_id do
      id when id == user.id ->
        race = Races.get_race!(participant.race_id, preload: [:categories, :auto_categories])

        splits = Races.list_splits(race.id)
        all_results = Results.get_race_results(race.id)
        result = Enum.find(all_results, fn r -> r.participant.id == participant.id end)
        rankings = Results.get_participant_rankings(race.id, participant.id)

        photos =
          if participant.bib_number,
            do: Photos.list_photos_for_bib(race.id, participant.bib_number),
            else: []

        {:ok,
         assign(socket,
           participant: participant,
           race: race,
           splits: splits,
           result: result,
           rankings: rankings,
           photos: photos,
           lightbox_photo: nil,
           page_title: race.name <> " — " <> gettext("My Result")
         )}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this result."))
         |> redirect(to: ~p"/profile")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-4 py-10">
      <%!-- Back link --%>
      <.link
        navigate={~p"/profile"}
        class="inline-flex items-center gap-1 text-sm text-primary hover:underline mb-6"
      >
        <.icon name="hero-arrow-left" class="size-4" />
        {gettext("Back to profile")}
      </.link>

      <%!-- Box 1: Race Result --%>
      <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden">
        <%!-- Race header --%>
        <div class="px-6 py-5 border-b border-base-300/40">
          <h1 class="text-2xl font-bold text-base-content">{@race.name}</h1>
          <div class="flex flex-wrap items-center gap-3 mt-1.5 text-sm text-base-content/50">
            <span :if={@race.date}>
              <.icon name="hero-calendar" class="size-4 inline -mt-0.5 mr-0.5" />
              {format_date(@race.date)}
            </span>
            <span :if={@race.location}>
              <.icon name="hero-map-pin" class="size-4 inline -mt-0.5 mr-0.5" />
              {@race.location}
            </span>
          </div>
        </div>

        <%!-- Status + Overall rank --%>
        <div class="px-6 py-5 border-b border-base-300/40 flex items-center gap-4">
          <div class={[
            "flex items-center justify-center w-16 h-16 rounded-2xl border",
            rank_badge_class(@result)
          ]}>
            <span :if={display_rank(@result)} class="text-2xl font-bold font-mono">
              {display_rank(@result)}
            </span>
            <span :if={!display_rank(@result)} class="text-lg font-semibold">
              {format_status_short(@result)}
            </span>
          </div>
          <div>
            <div class="text-lg font-bold text-base-content">
              {if @result && @result.status == :finished && @result.rank,
                do: gettext("Finished #%{rank}", rank: @result.rank),
                else: format_participant_status(if(@result, do: @result.status, else: :registered))}
            </div>
            <div
              :if={@result && @result.total_ms}
              class="font-mono text-2xl font-bold text-base-content mt-0.5"
            >
              {Calculator.format_time(@result.total_ms)}
            </div>
          </div>
        </div>

        <%!-- Split breakdown --%>
        <div :if={@splits != [] && @result} class="px-6 py-5 border-b border-base-300/40">
          <h2 class="text-sm font-medium text-base-content/60 uppercase tracking-wider mb-3">
            {gettext("Split Breakdown")}
          </h2>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs uppercase tracking-wider text-base-content/40">
                  <th class="text-left py-1.5 pr-4 font-semibold">{gettext("Split")}</th>
                  <th class="text-right py-1.5 pl-4 font-semibold">{gettext("Leg Time")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={split <- @splits} class="border-t border-base-300/30">
                  <td class="py-2 pr-4 text-base-content/70">{split.name}</td>
                  <td class="py-2 pl-4 text-right font-mono text-base-content">
                    {Calculator.format_time(Map.get(@result.leg_times, split.id))}
                  </td>
                </tr>
                <tr class="border-t-2 border-base-300/60 font-bold">
                  <td class="py-2 pr-4 text-base-content">{gettext("Total")}</td>
                  <td class="py-2 pl-4 text-right font-mono text-base-content">
                    {Calculator.format_time(@result.total_ms)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Rankings across all categories --%>
        <div class="px-6 py-5">
          <h2 class="text-sm font-medium text-base-content/60 uppercase tracking-wider mb-3">
            {gettext("Rankings")}
          </h2>
          <div class="space-y-2">
            <%!-- Overall --%>
            <.ranking_row
              label={gettext("Overall")}
              rank={@rankings.overall.rank}
              total={@rankings.overall.total}
            />

            <%!-- Manual category --%>
            <.ranking_row
              :if={@rankings.category}
              label={@rankings.category.category.name}
              rank={@rankings.category.rank}
              total={@rankings.category.total}
            />

            <%!-- Auto categories --%>
            <.ranking_row
              :for={ac <- @rankings.auto_categories}
              :if={ac.member}
              label={ac.auto_category.name}
              rank={ac.rank}
              total={ac.total}
            />
          </div>
        </div>
      </div>

      <%!-- Box 2: Race Photos --%>
      <div class="mt-6 rounded-xl bg-base-100 border border-base-300/50 shadow-sm px-6 py-8">
        <h2 class="text-sm font-medium text-base-content/60 uppercase tracking-wider mb-4">
          {gettext("Race Photos")}
          <span :if={@photos != []} class="text-base-content/40 ml-1">
            ({length(@photos)})
          </span>
        </h2>
        <%= if @photos != [] do %>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div
              :for={photo <- @photos}
              phx-click="open_lightbox"
              phx-value-id={photo.id}
              class="rounded-lg overflow-hidden aspect-square bg-base-200 cursor-pointer hover:opacity-90 transition-opacity"
            >
              <img
                src={Bibtime.Photos.display_url(photo)}
                alt={photo.caption || gettext("Race photo")}
                class="w-full h-full object-cover"
                loading="lazy"
              />
            </div>
          </div>
          <div class="mt-3 text-center">
            <.link
              navigate={~p"/races/#{@race.slug}/photos"}
              class="text-sm text-primary hover:underline"
            >
              {gettext("View all race photos")}
            </.link>
          </div>
        <% else %>
          <div class="flex flex-col items-center justify-center py-8 text-center">
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-full bg-base-200/60 mb-4">
              <.icon name="hero-camera" class="size-8 text-base-content/25" />
            </div>
            <p class="text-base-content/40 text-sm">
              {gettext("No photos available yet")}
            </p>
          </div>
        <% end %>
      </div>

      <%!-- Lightbox --%>
      <div
        :if={@lightbox_photo}
        phx-click="close_lightbox"
        phx-window-keydown="close_lightbox"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
      >
        <button
          phx-click="close_lightbox"
          class="absolute top-4 right-4 text-white/70 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-8" />
        </button>
        <img
          src={Bibtime.Photos.display_url(@lightbox_photo)}
          alt={@lightbox_photo.caption || gettext("Race photo")}
          class="max-w-full max-h-[85vh] rounded-lg object-contain"
        />
        <p :if={@lightbox_photo.caption} class="absolute bottom-6 text-white/80 text-sm">
          {@lightbox_photo.caption}
        </p>
      </div>

      <%!-- Link to full results --%>
      <div class="mt-4 text-center">
        <.link
          navigate={~p"/races/#{@race.slug}/results"}
          class="inline-flex items-center gap-1 text-sm text-primary hover:underline"
        >
          {gettext("View full results")}
          <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("open_lightbox", %{"id" => id}, socket) do
    photo = Enum.find(socket.assigns.photos, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, lightbox_photo: photo)}
  end

  def handle_event("close_lightbox", _params, socket) do
    {:noreply, assign(socket, lightbox_photo: nil)}
  end

  defp ranking_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2 px-3 rounded-lg bg-base-200/40">
      <span class="text-sm font-medium text-base-content/70">{@label}</span>
      <span class="font-mono text-sm font-bold text-base-content">
        <%= if @rank do %>
          {gettext("#%{rank} of %{total}", rank: @rank, total: @total)}
        <% else %>
          <span class="text-base-content/30">—</span>
        <% end %>
      </span>
    </div>
    """
  end

  defp display_rank(nil), do: nil

  defp display_rank(result) do
    if result.status == :finished && result.rank, do: result.rank
  end

  defp rank_badge_class(nil), do: "bg-base-200/60 border-base-300/50 text-base-content/40"

  defp rank_badge_class(result) do
    cond do
      result.status == :finished && result.rank == 1 ->
        "bg-warning/15 border-warning/30 text-warning"

      result.status == :finished && result.rank == 2 ->
        "bg-base-300/60 border-base-300 text-base-content/70"

      result.status == :finished && result.rank == 3 ->
        "bg-secondary/10 border-secondary/25 text-secondary"

      result.status == :finished ->
        "bg-success/8 border-success/20 text-success"

      result.status in [:dns, :dnf, :dsq] ->
        "bg-error/8 border-error/20 text-error"

      true ->
        "bg-base-200/60 border-base-300/50 text-base-content/40"
    end
  end

  defp format_status_short(nil), do: "--"

  defp format_status_short(result) do
    case result.status do
      :dns -> "DNS"
      :dnf -> "DNF"
      :dsq -> "DSQ"
      :racing -> "..."
      :registered -> "REG"
      :finished -> "--"
      _ -> "--"
    end
  end
end
