defmodule BibtimeWeb.Admin.RaceLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Races.RaceAutoCategory
  alias Bibtime.Races.RaceCategory
  alias Bibtime.Races.Split

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id, preload: [:categories, :auto_categories, :splits])

    {:ok,
     socket
     |> assign(:page_title, race.name)
     |> assign(:race, race)
     |> assign_category_form(Races.change_category(%RaceCategory{}))
     |> assign_auto_category_form(Races.change_auto_category(%RaceAutoCategory{}))
     |> assign_split_form(Races.change_split(%Split{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Header --%>
    <div class="flex items-start justify-between gap-6 pb-6">
      <div>
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">{@race.name}</h1>
          <.status_pill status={@race.status} />
        </div>
        <p class="mt-1 text-sm text-base-content/60 capitalize">{@race.race_type}</p>
      </div>
      <div class="flex items-center gap-2">
        <.link
          navigate={~p"/admin/races/new?clone_from=#{@race.id}"}
          class="btn btn-sm btn-ghost text-base-content/60 hover:text-base-content"
        >
          <.icon name="hero-document-duplicate" class="size-4 mr-1" /> {gettext("Clone")}
        </.link>
        <.button navigate={~p"/admin/races/#{@race.id}/edit"}>
          <.icon name="hero-pencil-square" class="size-4 mr-1" /> {gettext("Edit Race")}
        </.button>
      </div>
    </div>

    <%!-- Info Cards Grid --%>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <h3 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-3">
          {gettext("Details")}
        </h3>
        <dl class="space-y-3 text-sm">
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-calendar" class="size-4" /> {gettext("Date")}
            </dt>
            <dd class="font-medium">
              {if @race.date, do: format_date(@race.date), else: gettext("Not set")}
            </dd>
          </div>
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-map-pin" class="size-4" /> {gettext("Location")}
            </dt>
            <dd class="font-medium">{@race.location || gettext("Not set")}</dd>
          </div>
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-link" class="size-4" /> {gettext("Slug")}
            </dt>
            <dd class="font-mono text-xs bg-base-200 rounded px-2 py-0.5">{@race.slug}</dd>
          </div>
        </dl>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <h3 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-3">
          {gettext("Description")}
        </h3>
        <p class="text-sm text-base-content/80 leading-relaxed">
          {@race.description || gettext("No description provided.")}
        </p>
      </div>
    </div>

    <%!-- Quick Actions --%>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-6">
      <.link
        navigate={~p"/admin/races/#{@race.id}/participants"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-primary/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-primary/10 p-3">
          <.icon name="hero-users" class="size-6 text-primary" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-primary transition-colors">
            {gettext("Participants")}
          </div>
          <div class="text-sm text-base-content/50">{gettext("Manage race entrants")}</div>
        </div>
        <.icon
          name="hero-chevron-right"
          class="size-5 ml-auto text-base-content/30 group-hover:text-primary/60 transition-colors"
        />
      </.link>

      <.link
        navigate={~p"/admin/races/#{@race.id}/timing"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-secondary/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-secondary/10 p-3">
          <.icon name="hero-clock" class="size-6 text-secondary" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-secondary transition-colors">
            {gettext("Timing")}
          </div>
          <div class="text-sm text-base-content/50">{gettext("Race day console")}</div>
        </div>
        <.icon
          name="hero-chevron-right"
          class="size-5 ml-auto text-base-content/30 group-hover:text-secondary/60 transition-colors"
        />
      </.link>

      <a
        href={~p"/races/#{@race.slug}/kiosk"}
        target="_blank"
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-accent/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-accent/10 p-3">
          <.icon name="hero-tv" class="size-6 text-accent" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-accent transition-colors">
            {gettext("Kiosk Display")}
          </div>
          <div class="text-sm text-base-content/50">{gettext("Big-screen leaderboard")}</div>
        </div>
        <.icon
          name="hero-arrow-top-right-on-square"
          class="size-5 ml-auto text-base-content/30 group-hover:text-accent/60 transition-colors"
        />
      </a>

      <.link
        navigate={~p"/admin/races/#{@race.id}/photos"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-info/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-info/10 p-3">
          <.icon name="hero-photo" class="size-6 text-info" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-info transition-colors">
            {gettext("Photos")}
          </div>
          <div class="text-sm text-base-content/50">{gettext("Upload & tag race photos")}</div>
        </div>
        <.icon
          name="hero-chevron-right"
          class="size-5 ml-auto text-base-content/30 group-hover:text-info/60 transition-colors"
        />
      </.link>

      <.link
        :if={@race.payment_required}
        navigate={~p"/admin/races/#{@race.id}/payments"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-success/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-success/10 p-3">
          <.icon name="hero-banknotes" class="size-6 text-success" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-success transition-colors">
            {gettext("Payments")}
          </div>
          <div class="text-sm text-base-content/50">{gettext("Payment overview & refunds")}</div>
        </div>
        <.icon
          name="hero-chevron-right"
          class="size-5 ml-auto text-base-content/30 group-hover:text-success/60 transition-colors"
        />
      </.link>
    </div>

    <%!-- Categories Section --%>
    <div class="mt-10">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-tag" class="size-5 text-base-content/40" />
        <h2 class="text-lg font-semibold text-base-content">{gettext("Categories")}</h2>
      </div>

      <div
        :if={@race.categories != []}
        class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
      >
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">{gettext("Name")}</th>
              <th class="font-semibold">{gettext("Distance")}</th>
              <th class="font-semibold">{gettext("Gender")}</th>
              <th class="font-semibold">{gettext("Age Range")}</th>
              <th class="font-semibold">{gettext("Order")}</th>
              <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={cat <- @race.categories}
              id={"category-#{cat.id}"}
              class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
            >
              <td class="py-3 font-medium">{cat.name}</td>
              <td class="py-3 text-sm text-base-content/70">{cat.distance_label || "-"}</td>
              <td class="py-3 text-sm capitalize text-base-content/70">{cat.gender}</td>
              <td class="py-3 text-sm text-base-content/70">
                {format_age_range(cat.min_age, cat.max_age)}
              </td>
              <td class="py-3 text-sm text-base-content/70">{cat.sort_order}</td>
              <td class="py-3">
                <button
                  phx-click="delete_category"
                  phx-value-id={cat.id}
                  data-confirm={gettext("Are you sure you want to delete this category?")}
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  {gettext("Delete")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@race.categories == []} class="text-sm text-base-content/50 mb-4 italic">
        {gettext("No categories yet. Add one below.")}
      </p>

      <%!-- Add Category Form --%>
      <div class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" /> {gettext("Add Category")}
        </h3>
        <.form for={@category_form} phx-submit="add_category" class="flex flex-wrap gap-3 items-end">
          <.input
            field={@category_form[:name]}
            type="text"
            label={gettext("Name")}
            required
            placeholder={gettext("e.g. Elite Men")}
          />
          <.input
            field={@category_form[:distance_label]}
            type="text"
            label={gettext("Distance")}
            placeholder={gettext("e.g. 5K")}
          />
          <.input
            field={@category_form[:gender]}
            type="select"
            label={gettext("Gender")}
            options={[{gettext("Any"), :any}, {gettext("Male"), :male}, {gettext("Female"), :female}]}
          />
          <.input field={@category_form[:min_age]} type="number" label={gettext("Min Age")} />
          <.input field={@category_form[:max_age]} type="number" label={gettext("Max Age")} />
          <.input
            field={@category_form[:sort_order]}
            type="number"
            label={gettext("Order")}
            value="0"
          />
          <.button type="submit" variant="primary">{gettext("Add")}</.button>
        </.form>
      </div>
    </div>

    <%!-- Auto Categories Section --%>
    <div class="mt-10">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-bolt" class="size-5 text-base-content/40" />
        <h2 class="text-lg font-semibold text-base-content">{gettext("Auto Categories")}</h2>
      </div>

      <div
        :if={@race.auto_categories != []}
        class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
      >
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">{gettext("Name")}</th>
              <th class="font-semibold">{gettext("Type")}</th>
              <th class="font-semibold">{gettext("Details")}</th>
              <th class="font-semibold">{gettext("Order")}</th>
              <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={auto_cat <- @race.auto_categories}
              id={"auto-category-#{auto_cat.id}"}
              class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
            >
              <td class="py-3 font-medium">{auto_cat.name}</td>
              <td class="py-3 text-sm capitalize text-base-content/70">
                {format_auto_cat_type(auto_cat.type)}
              </td>
              <td class="py-3 text-sm text-base-content/70">
                {format_auto_cat_details(auto_cat)}
              </td>
              <td class="py-3 text-sm text-base-content/70">{auto_cat.sort_order}</td>
              <td class="py-3">
                <button
                  phx-click="delete_auto_category"
                  phx-value-id={auto_cat.id}
                  data-confirm={gettext("Are you sure you want to delete this auto category?")}
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  {gettext("Delete")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@race.auto_categories == []} class="text-sm text-base-content/50 mb-4 italic">
        {gettext("No auto categories yet. Use the quick-add buttons or add one manually below.")}
      </p>

      <%!-- Quick-add presets --%>
      <div class="mt-4 flex flex-wrap gap-2">
        <button
          phx-click="add_gender_auto_categories"
          class="btn btn-sm btn-outline gap-1.5"
        >
          <.icon name="hero-plus" class="size-3.5" /> {gettext("Add Gender Categories")}
        </button>
        <button
          phx-click="add_age_group_auto_categories"
          class="btn btn-sm btn-outline gap-1.5"
        >
          <.icon name="hero-plus" class="size-3.5" /> {gettext("Add Standard Age Groups")}
        </button>
      </div>

      <%!-- Add Auto Category Form --%>
      <div class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" /> {gettext(
            "Add Auto Category"
          )}
        </h3>
        <.form
          for={@auto_category_form}
          phx-submit="add_auto_category"
          class="flex flex-wrap gap-3 items-end"
        >
          <.input
            field={@auto_category_form[:name]}
            type="text"
            label={gettext("Name")}
            required
            placeholder={gettext("e.g. Men, 20-29")}
          />
          <.input
            field={@auto_category_form[:type]}
            type="select"
            label={gettext("Type")}
            options={[{gettext("Gender"), :gender}, {gettext("Age Group"), :age_group}]}
            required
          />
          <.input
            field={@auto_category_form[:gender_value]}
            type="select"
            label={gettext("Gender Value")}
            prompt={gettext("(for gender type)")}
            options={[
              {gettext("Male"), :male},
              {gettext("Female"), :female},
              {gettext("Other"), :other}
            ]}
          />
          <.input field={@auto_category_form[:min_age]} type="number" label={gettext("Min Age")} />
          <.input field={@auto_category_form[:max_age]} type="number" label={gettext("Max Age")} />
          <.input
            field={@auto_category_form[:sort_order]}
            type="number"
            label={gettext("Order")}
            value="0"
          />
          <.button type="submit" variant="primary">{gettext("Add")}</.button>
        </.form>
      </div>
    </div>

    <%!-- Splits Section --%>
    <div class="mt-10">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-scissors" class="size-5 text-base-content/40" />
        <h2 class="text-lg font-semibold text-base-content">{gettext("Splits")}</h2>
      </div>

      <div
        :if={@race.splits != []}
        class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
      >
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">{gettext("Name")}</th>
              <th class="font-semibold">{gettext("Short Name")}</th>
              <th class="font-semibold">{gettext("Leg Type")}</th>
              <th class="font-semibold">{gettext("Distance (m)")}</th>
              <th class="font-semibold">{gettext("Order")}</th>
              <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={split <- @race.splits}
              id={"split-#{split.id}"}
              class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30"
            >
              <td class="py-3 font-medium">{split.name}</td>
              <td class="py-3 text-sm font-mono text-base-content/70">{split.short_name}</td>
              <td class="py-3 text-sm capitalize text-base-content/70">{split.leg_type}</td>
              <td class="py-3 text-sm text-base-content/70">{split.distance_meters || "-"}</td>
              <td class="py-3 text-sm text-base-content/70">{split.sort_order}</td>
              <td class="py-3">
                <button
                  phx-click="delete_split"
                  phx-value-id={split.id}
                  data-confirm={gettext("Are you sure you want to delete this split?")}
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  {gettext("Delete")}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@race.splits == []} class="text-sm text-base-content/50 mb-4 italic">
        {gettext("No splits yet. Add one below.")}
      </p>

      <%!-- Add Split Form --%>
      <div class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" /> {gettext("Add Split")}
        </h3>
        <.form for={@split_form} phx-submit="add_split" class="flex flex-wrap gap-3 items-end">
          <.input
            field={@split_form[:name]}
            type="text"
            label={gettext("Name")}
            required
            placeholder={gettext("e.g. Swim")}
          />
          <.input
            field={@split_form[:short_name]}
            type="text"
            label={gettext("Short Name")}
            required
            placeholder={gettext("e.g. S1")}
          />
          <.input
            field={@split_form[:leg_type]}
            type="select"
            label={gettext("Leg Type")}
            options={[
              {gettext("Swim"), :swim},
              {gettext("Bike"), :bike},
              {gettext("Run"), :run},
              {gettext("Transition"), :transition},
              {gettext("Other"), :other}
            ]}
            required
          />
          <.input field={@split_form[:distance_meters]} type="number" label={gettext("Distance (m)")} />
          <.input field={@split_form[:sort_order]} type="number" label={gettext("Order")} value="0" />
          <.button type="submit" variant="primary">{gettext("Add")}</.button>
        </.form>
      </div>
    </div>

    <div class="mt-10 pt-4 border-t border-base-200">
      <.link
        navigate={~p"/admin/races"}
        class="text-sm text-base-content/50 hover:text-primary transition-colors flex items-center gap-1"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> {gettext("Back to races")}
      </.link>
    </div>
    """
  end

  @impl true
  def handle_event("add_category", %{"race_category" => category_params}, socket) do
    category_params = Map.put(category_params, "race_id", socket.assigns.race.id)

    case Races.create_category(category_params) do
      {:ok, _category} ->
        race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

        {:noreply,
         socket
         |> assign(:race, race)
         |> assign_category_form(Races.change_category(%RaceCategory{}))
         |> put_flash(:info, gettext("Category added."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_category_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Races.get_category!(id)
    {:ok, _} = Races.delete_category(category)
    race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, gettext("Category deleted."))}
  end

  @impl true
  def handle_event("add_auto_category", %{"race_auto_category" => params}, socket) do
    params = Map.put(params, "race_id", socket.assigns.race.id)

    case Races.create_auto_category(params) do
      {:ok, _auto_category} ->
        race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

        {:noreply,
         socket
         |> assign(:race, race)
         |> assign_auto_category_form(Races.change_auto_category(%RaceAutoCategory{}))
         |> put_flash(:info, gettext("Auto category added."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_auto_category_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_auto_category", %{"id" => id}, socket) do
    auto_category = Races.get_auto_category!(id)
    {:ok, _} = Races.delete_auto_category(auto_category)
    race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, gettext("Auto category deleted."))}
  end

  @impl true
  def handle_event("add_gender_auto_categories", _params, socket) do
    Races.add_gender_auto_categories(socket.assigns.race.id)
    race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, gettext("Gender categories added."))}
  end

  @impl true
  def handle_event("add_age_group_auto_categories", _params, socket) do
    Races.add_age_group_auto_categories(socket.assigns.race.id)
    race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, gettext("Age group categories added."))}
  end

  @impl true
  def handle_event("add_split", %{"split" => split_params}, socket) do
    split_params = Map.put(split_params, "race_id", socket.assigns.race.id)

    case Races.create_split(split_params) do
      {:ok, _split} ->
        race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

        {:noreply,
         socket
         |> assign(:race, race)
         |> assign_split_form(Races.change_split(%Split{}))
         |> put_flash(:info, gettext("Split added."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_split_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_split", %{"id" => id}, socket) do
    split = Races.get_split!(id)
    {:ok, _} = Races.delete_split(split)
    race = Races.get_race!(socket.assigns.race.id, preload: [:categories, :auto_categories, :splits])

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, gettext("Split deleted."))}
  end

  defp assign_category_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :category_form, to_form(changeset))
  end

  defp assign_auto_category_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :auto_category_form, to_form(changeset))
  end

  defp assign_split_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :split_form, to_form(changeset))
  end

  defp format_auto_cat_type(:gender), do: gettext("Gender")
  defp format_auto_cat_type(:age_group), do: gettext("Age Group")
  defp format_auto_cat_type(type), do: to_string(type)

  defp format_auto_cat_details(%{type: :gender, gender_value: gv}) when not is_nil(gv) do
    gettext("Gender = %{value}", value: gv)
  end

  defp format_auto_cat_details(%{type: :age_group, min_age: min, max_age: max}) do
    format_age_range(min, max)
  end

  defp format_auto_cat_details(_), do: "-"

  defp format_age_range(nil, nil), do: gettext("Any")
  defp format_age_range(min, nil), do: "#{min}+"
  defp format_age_range(nil, max), do: gettext("Up to %{max}", max: max)
  defp format_age_range(min, max), do: "#{min}-#{max}"
end
