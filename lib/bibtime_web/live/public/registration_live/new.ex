defmodule BibtimeWeb.Public.RegistrationLive.New do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Participants
  alias Bibtime.Payments
  alias Bibtime.Registration
  alias Bibtime.Participants.Participant

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    race =
      slug
      |> Races.get_race_by_slug!()
      |> Bibtime.Repo.preload([:categories, :auto_categories])

    registration_full = Registration.registration_full?(race)

    if Registration.registration_open?(race) && !registration_full do
      has_manual_categories = race.categories != []
      auto_cat_types = race.auto_categories |> Enum.map(& &1.type) |> Enum.uniq()
      requires_gender = :gender in auto_cat_types
      requires_birth_date = :age_group in auto_cat_types

      reg_opts = [
        require_category: has_manual_categories,
        require_gender: requires_gender,
        require_birth_date: requires_birth_date
      ]

      # Prefill order:
      #   1. A pending-payment participant the user just submitted but
      #      bailed on at Stripe (carried by `:pending_participant_id`
      #      session cookie set by CheckoutController). This is the "back
      #      button after Stripe" case — same race, same form.
      #   2. The current user's most recent registration (cross-race
      #      defaults, eg. name + birth date). Existing behavior.
      prefill_attrs =
        case prefill_attrs_for_pending_participant(session, race.id) do
          %{} = attrs when map_size(attrs) > 0 -> attrs
          _ -> prefill_attrs_for_user(socket.assigns.current_scope)
        end

      changeset = Registration.change_registration(%Participant{}, prefill_attrs, reg_opts)

      fee_cents = Payments.effective_fee_cents(race)

      {:ok,
       assign(socket,
         race: race,
         form: to_form(changeset),
         has_manual_categories: has_manual_categories,
         requires_gender: requires_gender,
         requires_birth_date: requires_birth_date,
         reg_opts: reg_opts,
         fee_cents: fee_cents,
         user_registrations: user_registrations(socket.assigns.current_scope, race.id),
         duplicate_error: nil,
         page_title: gettext("Register") <> " — " <> race.name
       )}
    else
      {:ok,
       assign(socket,
         race: race,
         form: nil,
         fee_cents: 0,
         registration_full: registration_full,
         user_registrations: user_registrations(socket.assigns.current_scope, race.id),
         duplicate_error: nil,
         page_title: gettext("Registration") <> " — " <> race.name
       )}
    end
  end

  defp user_registrations(%{user: %{id: user_id}}, race_id) when not is_nil(user_id) do
    now = DateTime.utc_now()

    user_id
    |> Participants.list_user_participants_in_race(race_id)
    |> Enum.filter(fn p ->
      # Show the "you already have a registration" banner only for rows
      # the user can actually act on right now: a confirmed registration
      # with a bib, or a still-active hold. A pending row with no bib and
      # an expired hold is effectively abandoned — re-submitting the form
      # will refresh it via the resume path, no need to warn them.
      not is_nil(p.bib_number) or
        (p.status == :pending_payment and p.hold_expires_at &&
           DateTime.compare(p.hold_expires_at, now) == :gt)
    end)
  end

  defp user_registrations(_, _), do: []

  @impl true
  def handle_event("validate", %{"participant" => params}, socket) do
    changeset =
      %Participant{}
      |> Registration.change_registration(params, socket.assigns.reg_opts)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset), duplicate_error: nil)}
  end

  @impl true
  def handle_event("save", %{"participant" => params}, socket) do
    race = socket.assigns.race

    case Registration.register_participant(race, params) do
      {:ok, participant} ->
        if race.payment_required do
          # Full HTTP redirect through CheckoutController so the session
          # cookie can be written before the user lands on Stripe — that
          # cookie is what lets the form pre-fill itself if the user hits
          # the browser back button after abandoning checkout.
          {:noreply,
           redirect(socket, to: ~p"/races/#{race.slug}/checkout/#{participant.id}")}
        else
          {:noreply,
           socket
           |> put_flash(:info, gettext("You're registered!"))
           |> push_navigate(to: ~p"/races/#{race.slug}/register/confirmation/#{participant.id}")}
        end

      {:error, :duplicate, existing} ->
        {:noreply, handle_duplicate(socket, race, existing)}

      {:error, :race_full} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext(
             "This race filled up while your hold was expired. Your previous payment attempt can't be resumed."
           )
         )
         |> push_navigate(to: ~p"/races/#{race.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp handle_duplicate(socket, race, %Participant{} = existing) do
    current_user_id =
      case socket.assigns[:current_scope] do
        %{user: %{id: id}} -> id
        _ -> nil
      end

    owned_by_current_user? = current_user_id && existing.user_id == current_user_id

    if owned_by_current_user? do
      push_navigate(socket,
        to: ~p"/races/#{race.slug}/my-registration/#{existing.confirmation_token}"
      )
    else
      assign(socket, duplicate_error: existing)
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

      <%!-- Duplicate-submission error --%>
      <div
        :if={@duplicate_error}
        class="rounded-lg bg-error/10 border border-error/30 px-5 py-4 mb-6 flex items-start gap-3"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 text-error shrink-0 mt-0.5" />
        <div>
          <p class="text-sm font-semibold text-base-content">
            {gettext("%{name} (%{email}) is already registered for this race.",
              name: duplicate_display_name(@duplicate_error),
              email: @duplicate_error.email
            )}
          </p>
          <p class="text-xs text-base-content/60 mt-1">
            {gettext("If you're registering a different person, change the name or email.")}
          </p>
        </div>
      </div>

      <%!-- Existing registrations banner (for logged-in users) --%>
      <div
        :if={@user_registrations != []}
        class="rounded-lg bg-success/10 border border-success/20 px-5 py-4 mb-6"
      >
        <div class="flex items-start gap-3">
          <.icon name="hero-check-circle" class="size-5 text-success shrink-0 mt-0.5" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-base-content">
              {ngettext(
                "You already have a registration for this race.",
                "You already have %{count} registrations for this race.",
                length(@user_registrations),
                count: length(@user_registrations)
              )}
            </p>
            <p class="text-xs text-base-content/60 mt-0.5">
              {gettext("Only continue if you're registering someone else.")}
            </p>
            <ul class="mt-3 space-y-1.5">
              <li
                :for={p <- @user_registrations}
                class="flex items-center gap-2 text-sm"
              >
                <span class="inline-flex items-center justify-center rounded-md bg-primary/10 font-mono text-xs font-bold text-primary px-2 py-0.5">
                  {p.bib_number}
                </span>
                <span class="text-base-content">
                  {p.first_name} {p.last_name}
                </span>
                <.link
                  navigate={~p"/races/#{@race.slug}/my-registration/#{p.confirmation_token}"}
                  class="ml-auto text-xs text-primary hover:underline inline-flex items-center gap-1"
                >
                  {gettext("View")} <.icon name="hero-arrow-right" class="size-3" />
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <%!-- Entry fee banner --%>
      <div
        :if={@race.payment_required && @form != nil}
        class="rounded-lg bg-info/10 border border-info/20 px-5 py-4 mb-6 flex items-center gap-3"
      >
        <.icon name="hero-credit-card" class="size-5 text-info shrink-0" />
        <div>
          <p class="text-sm font-medium text-base-content">
            {gettext("Entry fee")}: {Payments.format_amount(@fee_cents, @race.currency)}
          </p>
          <p
            :if={
              @race.early_bird_fee_cents && @race.early_bird_deadline &&
                @fee_cents == @race.early_bird_fee_cents
            }
            class="text-xs text-base-content/50"
          >
            {gettext("Early bird pricing until %{date}", date: format_date(@race.early_bird_deadline))}
          </p>
        </div>
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
            <% @registration_full -> %>
              {gettext("Registration is full")}
            <% @race.status == :draft -> %>
              {gettext("Registration is not yet open")}
            <% @race.status in [:in_progress, :finished] -> %>
              {gettext("This race has already started")}
            <% true -> %>
              {gettext("Registration is closed")}
          <% end %>
        </h2>
        <p class="text-base-content/50 mb-6">
          <%= if @registration_full do %>
            {gettext("All available spots have been taken. Check back later in case spots open up.")}
          <% else %>
            {gettext("Check back later or view the results page for updates.")}
          <% end %>
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
            <.input field={@form[:last_name]} type="text" label={gettext("Last Name")} />
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
              <%= if @race.payment_required do %>
                <.icon name="hero-credit-card" class="size-5" />
                {gettext("Register & Pay %{amount}",
                  amount: Payments.format_amount(@fee_cents, @race.currency)
                )}
              <% else %>
                <.icon name="hero-check-circle" class="size-5" />
                {gettext("Complete Registration")}
              <% end %>
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp duplicate_display_name(%Participant{first_name: first, last_name: last}) do
    String.trim("#{first} #{last || ""}")
  end

  # Hits when CheckoutController set `:pending_participant_id` on the way to
  # Stripe and the user is now back on the form (typically via browser back).
  # We only honour the cookie if the participant belongs to *this* race and
  # is still in :pending_payment — otherwise it's stale and we ignore it.
  defp prefill_attrs_for_pending_participant(%{"pending_participant_id" => id}, race_id)
       when is_integer(id) do
    case Participants.get_participant!(id) do
      %Participant{race_id: ^race_id, status: :pending_payment} = p ->
        %{
          "first_name" => p.first_name,
          "last_name" => p.last_name,
          "email" => p.email,
          "gender" => if(p.gender, do: Atom.to_string(p.gender)),
          "birth_date" => if(p.birth_date, do: Date.to_iso8601(p.birth_date)),
          "club" => p.club,
          "race_category_id" => p.race_category_id
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      _ ->
        %{}
    end
  rescue
    Ecto.NoResultsError -> %{}
  end

  defp prefill_attrs_for_pending_participant(_session, _race_id), do: %{}

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
