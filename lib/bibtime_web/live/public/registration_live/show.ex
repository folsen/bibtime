defmodule BibtimeWeb.Public.RegistrationLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Payments

  @impl true
  def mount(%{"slug" => slug, "participant_id" => participant_id}, _session, socket) do
    race = Races.get_race_by_slug!(slug)

    participant =
      Participants.get_participant!(participant_id)
      |> Bibtime.Repo.preload([:race_category, :user])

    payment = Payments.get_payment_for_participant(participant.id)

    # If payment is pending, check Stripe directly (webhook fallback)
    {participant, payment} =
      case payment do
        %{status: :pending} ->
          case Payments.check_and_fulfill_payment(payment) do
            {:ok, %{status: :completed} = updated_payment} ->
              # Re-fetch participant since status may have changed
              updated_participant =
                Participants.get_participant!(participant_id)
                |> Bibtime.Repo.preload([:race_category, :user])

              {updated_participant, updated_payment}

            _ ->
              {participant, payment}
          end

        _ ->
          {participant, payment}
      end

    {:ok,
     assign(socket,
       race: race,
       participant: participant,
       payment: payment,
       page_title: gettext("Registration Confirmed") <> " — " <> race.name
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-10">
      <div class="rounded-xl bg-base-100 border border-base-300/50 shadow-sm overflow-hidden">
        <%!-- Success banner for registered participants --%>
        <div
          :if={@participant.status != :pending_payment}
          class="bg-success/10 border-b border-success/20 px-8 py-6 text-center"
        >
          <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-success/20 mb-3">
            <.icon name="hero-check-circle" class="size-8 text-success" />
          </div>
          <h1 class="text-2xl font-bold text-base-content mb-1">{gettext("You're Registered!")}</h1>
          <p :if={@participant.user && @participant.user.email} class="text-base-content/60 text-sm">
            {gettext("A confirmation email has been sent to %{email}",
              email: @participant.user.email
            )}
          </p>
        </div>

        <%!-- Pending payment banner --%>
        <div
          :if={@participant.status == :pending_payment}
          class="bg-warning/10 border-b border-warning/20 px-8 py-6 text-center"
        >
          <div class="inline-flex items-center justify-center w-14 h-14 rounded-full bg-warning/20 mb-3">
            <.icon name="hero-clock" class="size-8 text-warning" />
          </div>
          <h1 class="text-2xl font-bold text-base-content mb-1">
            {gettext("Awaiting Payment")}
          </h1>
          <p class="text-base-content/60 text-sm">
            {gettext("Your registration will be confirmed once payment is received.")}
          </p>
        </div>

        <%!-- Details --%>
        <div class="px-8 py-6 space-y-5">
          <%!-- Bib number highlight (hidden until payment clears) --%>
          <div :if={@participant.bib_number} class="text-center py-4">
            <p class="text-xs uppercase tracking-widest text-base-content/40 font-semibold mb-2">
              {gettext("Your Bib Number")}
            </p>
            <span class="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-primary/10 border-2 border-primary/30">
              <span class="text-3xl font-bold font-mono text-primary">{@participant.bib_number}</span>
            </span>
          </div>
          <div :if={is_nil(@participant.bib_number)} class="text-center py-4">
            <p class="text-xs uppercase tracking-widest text-base-content/40 font-semibold mb-2">
              {gettext("Bib Number")}
            </p>
            <p class="text-sm text-base-content/60">
              {gettext("Your bib will be assigned once payment is received.")}
            </p>
          </div>

          <div class="divide-y divide-base-300/30">
            <div class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Race")}</span>
              <span class="text-sm font-medium text-base-content">{@race.name}</span>
            </div>
            <div :if={@race.date} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Date")}</span>
              <span class="text-sm font-medium text-base-content">
                {format_date(@race.date)}
              </span>
            </div>
            <div :if={@race.location} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Location")}</span>
              <span class="text-sm font-medium text-base-content">{@race.location}</span>
            </div>
            <div class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Name")}</span>
              <span class="text-sm font-medium text-base-content">
                {@participant.first_name} {@participant.last_name}
              </span>
            </div>
            <div :if={@participant.race_category} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Category")}</span>
              <span class="text-sm font-medium text-base-content">
                {@participant.race_category.name}
              </span>
            </div>
            <div :if={@participant.club} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Club")}</span>
              <span class="text-sm font-medium text-base-content">{@participant.club}</span>
            </div>
            <div :if={@payment} class="flex justify-between py-3">
              <span class="text-sm text-base-content/50">{gettext("Payment")}</span>
              <span class={[
                "text-sm font-medium",
                @payment.status == :completed && "text-success",
                @payment.status == :pending && "text-warning",
                @payment.status == :refunded && "text-base-content/50",
                @payment.status == :failed && "text-error"
              ]}>
                {payment_status_label(@payment.status)} — {Payments.format_amount(
                  @payment.amount_cents,
                  @payment.currency
                )}
              </span>
            </div>
          </div>
        </div>

        <%!-- Actions --%>
        <div class="px-8 py-5 bg-base-200/30 border-t border-base-300/30 flex flex-wrap gap-3">
          <button
            :if={@participant.status == :pending_payment && @race.payment_required}
            type="button"
            phx-click="resume_payment"
            class="btn btn-warning btn-sm gap-1.5"
          >
            <.icon name="hero-credit-card" class="size-4" /> {gettext("Continue to Payment")}
          </button>
          <.link
            navigate={~p"/races/#{@race.slug}"}
            class="btn btn-outline btn-primary btn-sm gap-1.5"
          >
            <.icon name="hero-arrow-right" class="size-4" /> {gettext("View Race")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("resume_payment", _params, socket) do
    %{race: race, participant: participant} = socket.assigns
    base_url = BibtimeWeb.Endpoint.url()
    success_url = base_url <> ~p"/races/#{race.slug}/register/confirmation/#{participant.id}"
    cancel_url = base_url <> ~p"/races/#{race.slug}/register/confirmation/#{participant.id}"

    case Payments.create_checkout_session(participant, race, success_url, cancel_url) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, gettext("Payment setup failed: %{reason}", reason: reason))}
    end
  end

  defp payment_status_label(:completed), do: gettext("Paid")
  defp payment_status_label(:pending), do: gettext("Pending")
  defp payment_status_label(:refunded), do: gettext("Refunded")
  defp payment_status_label(:failed), do: gettext("Failed")
end
