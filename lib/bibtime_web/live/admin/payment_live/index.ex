defmodule BibtimeWeb.Admin.PaymentLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Payments
  alias Bibtime.AuditLog

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)
    payments = Payments.list_payments_for_race(race.id)
    summary = Payments.race_payment_summary(race.id)

    {:ok,
     socket
     |> assign(:page_title, gettext("Payments") <> " — " <> race.name)
     |> assign(:race, race)
     |> assign(:payments, payments)
     |> assign(:summary, summary)
     |> assign(:confirm_refund_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-6">
      <div class="flex items-center gap-2 mb-1">
        <.link
          navigate={~p"/admin/races/#{@race.id}"}
          class="text-base-content/50 hover:text-base-content transition-colors"
        >
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Payments")}
        </h1>
      </div>
      <p class="mt-1 text-sm text-base-content/60">{@race.name}</p>
    </div>

    <%!-- Summary cards --%>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <p class="text-xs text-base-content/50 uppercase tracking-wider font-semibold">
          {gettext("Total Collected")}
        </p>
        <p class="mt-2 text-2xl font-bold text-success font-mono">
          {Payments.format_amount(@summary.total_collected_cents, @summary.currency || @race.currency)}
        </p>
        <p class="text-xs text-base-content/40 mt-1">
          {ngettext("1 payment", "%{count} payments", @summary.completed_count)}
        </p>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <p class="text-xs text-base-content/50 uppercase tracking-wider font-semibold">
          {gettext("Pending")}
        </p>
        <p class="mt-2 text-2xl font-bold text-warning font-mono">
          {Payments.format_amount(@summary.total_pending_cents, @summary.currency || @race.currency)}
        </p>
        <p class="text-xs text-base-content/40 mt-1">
          {ngettext("1 payment", "%{count} payments", @summary.pending_count)}
        </p>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <p class="text-xs text-base-content/50 uppercase tracking-wider font-semibold">
          {gettext("Refunded")}
        </p>
        <p class="mt-2 text-2xl font-bold text-base-content/50 font-mono">
          {Payments.format_amount(@summary.total_refunded_cents, @summary.currency || @race.currency)}
        </p>
        <p class="text-xs text-base-content/40 mt-1">
          {ngettext("1 payment", "%{count} payments", @summary.refunded_count)}
        </p>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <p class="text-xs text-base-content/50 uppercase tracking-wider font-semibold">
          {gettext("Entry Fee")}
        </p>
        <p class="mt-2 text-2xl font-bold text-base-content font-mono">
          {Payments.format_amount(@race.entry_fee_cents, @race.currency)}
        </p>
        <p :if={@race.early_bird_fee_cents} class="text-xs text-base-content/40 mt-1">
          {gettext("Early bird")}: {Payments.format_amount(@race.early_bird_fee_cents, @race.currency)}
        </p>
      </div>
    </div>

    <%!-- Payments table --%>
    <div class="rounded-xl border border-base-300 bg-base-100 shadow-sm overflow-hidden">
      <div class="px-5 py-4 border-b border-base-300 flex items-center justify-between">
        <h2 class="font-semibold text-base-content">{gettext("All Payments")}</h2>
        <span class="text-sm text-base-content/50">
          {ngettext("1 payment", "%{count} payments", length(@payments))}
        </span>
      </div>

      <div :if={@payments == []} class="px-8 py-12 text-center text-base-content/40">
        <.icon name="hero-banknotes" class="size-10 mx-auto mb-3 opacity-30" />
        <p>{gettext("No payments yet")}</p>
      </div>

      <table :if={@payments != []} class="table w-full">
        <thead>
          <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
            <th class="font-semibold">{gettext("Participant")}</th>
            <th class="font-semibold">{gettext("Amount")}</th>
            <th class="font-semibold">{gettext("Status")}</th>
            <th class="font-semibold">{gettext("Date")}</th>
            <th class="font-semibold text-right">{gettext("Actions")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={payment <- @payments} class="border-b border-base-300/50 hover:bg-base-200/30">
            <td class="py-3">
              <div class="font-medium text-sm">
                {payment.participant.first_name} {payment.participant.last_name}
              </div>
              <div class="text-xs text-base-content/40">{payment.participant.email}</div>
            </td>
            <td class="py-3 font-mono text-sm">
              {Payments.format_amount(payment.amount_cents, payment.currency)}
            </td>
            <td class="py-3">
              <span class={[
                "rounded-full px-2.5 py-0.5 text-xs font-medium",
                payment_status_class(payment.status)
              ]}>
                {payment_status_label(payment.status)}
              </span>
            </td>
            <td class="py-3 text-sm text-base-content/60">
              {format_date_short(payment.paid_at || payment.inserted_at)}
            </td>
            <td class="py-3 text-right">
              <%= if payment.status == :completed do %>
                <%= if @confirm_refund_id == payment.id do %>
                  <div class="flex items-center justify-end gap-2">
                    <button
                      phx-click="confirm_refund"
                      phx-value-id={payment.id}
                      class="btn btn-error btn-xs"
                    >
                      {gettext("Confirm")}
                    </button>
                    <button
                      phx-click="cancel_refund"
                      class="btn btn-ghost btn-xs"
                    >
                      {gettext("Cancel")}
                    </button>
                  </div>
                <% else %>
                  <button
                    phx-click="refund"
                    phx-value-id={payment.id}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-3.5" /> {gettext("Refund")}
                  </button>
                <% end %>
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <%!-- Comp registration section --%>
    <div class="mt-8 rounded-xl border border-dashed border-base-300 bg-base-100 p-6 shadow-sm">
      <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider mb-2">
        {gettext("Complimentary Registration")}
      </h3>
      <p class="text-sm text-base-content/50 mb-4">
        {gettext("To register a participant without payment, use the regular")}
        <.link
          navigate={~p"/admin/races/#{@race.id}/participants/new"}
          class="text-primary hover:underline"
        >
          {gettext("Add Participant")}
        </.link>
        {gettext("form. Admin-added participants skip the payment requirement.")}
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("refund", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_refund_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_refund", _params, socket) do
    {:noreply, assign(socket, :confirm_refund_id, nil)}
  end

  @impl true
  def handle_event("confirm_refund", %{"id" => id}, socket) do
    payment = Payments.get_payment!(id)

    case Payments.refund_payment(payment) do
      {:ok, _payment} ->
        AuditLog.log(
          socket.assigns.current_scope.user,
          "payment.refunded",
          "payment",
          payment.id,
          %{
            "participant_id" => payment.participant_id,
            "amount_cents" => payment.amount_cents,
            "currency" => payment.currency
          }
        )

        race = socket.assigns.race
        payments = Payments.list_payments_for_race(race.id)
        summary = Payments.race_payment_summary(race.id)

        {:noreply,
         socket
         |> put_flash(:info, gettext("Payment refunded successfully."))
         |> assign(:payments, payments)
         |> assign(:summary, summary)
         |> assign(:confirm_refund_id, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Refund failed: %{reason}", reason: reason))
         |> assign(:confirm_refund_id, nil)}
    end
  end

  defp payment_status_class(:completed), do: "bg-success/15 text-success"
  defp payment_status_class(:pending), do: "bg-warning/15 text-warning"
  defp payment_status_class(:refunded), do: "bg-base-300/50 text-base-content/50"
  defp payment_status_class(:failed), do: "bg-error/15 text-error"

  defp payment_status_label(:completed), do: gettext("Paid")
  defp payment_status_label(:pending), do: gettext("Pending")
  defp payment_status_label(:refunded), do: gettext("Refunded")
  defp payment_status_label(:failed), do: gettext("Failed")
end
