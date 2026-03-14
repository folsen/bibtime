defmodule BibtimeWeb.Admin.RaceLive.Show do
  use BibtimeWeb, :live_view

  alias Bibtime.Races
  alias Bibtime.Races.RaceCategory
  alias Bibtime.Races.Split

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    race = Races.get_race!(id)

    {:ok,
     socket
     |> assign(:page_title, race.name)
     |> assign(:race, race)
     |> assign_category_form(Races.change_category(%RaceCategory{}))
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
          <span class={["rounded-full px-2.5 py-0.5 text-xs font-medium", status_pill_class(@race.status)]}>
            {format_status(@race.status)}
          </span>
        </div>
        <p class="mt-1 text-sm text-base-content/60 capitalize">{@race.race_type}</p>
      </div>
      <.button navigate={~p"/admin/races/#{@race.id}/edit"}>
        <.icon name="hero-pencil-square" class="size-4 mr-1" /> Edit Race
      </.button>
    </div>

    <%!-- Info Cards Grid --%>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <h3 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-3">Details</h3>
        <dl class="space-y-3 text-sm">
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-calendar" class="size-4" /> Date
            </dt>
            <dd class="font-medium">{if @race.date, do: Calendar.strftime(@race.date, "%B %d, %Y"), else: "Not set"}</dd>
          </div>
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-map-pin" class="size-4" /> Location
            </dt>
            <dd class="font-medium">{@race.location || "Not set"}</dd>
          </div>
          <div class="flex items-center justify-between">
            <dt class="text-base-content/50 flex items-center gap-1.5">
              <.icon name="hero-link" class="size-4" /> Slug
            </dt>
            <dd class="font-mono text-xs bg-base-200 rounded px-2 py-0.5">{@race.slug}</dd>
          </div>
        </dl>
      </div>

      <div class="rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm">
        <h3 class="text-sm font-semibold text-base-content/50 uppercase tracking-wider mb-3">Description</h3>
        <p class="text-sm text-base-content/80 leading-relaxed">{@race.description || "No description provided."}</p>
      </div>
    </div>

    <%!-- Quick Actions --%>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-6">
      <.link
        navigate={~p"/admin/races/#{@race.id}/participants"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-primary/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-primary/10 p-3">
          <.icon name="hero-users" class="size-6 text-primary" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-primary transition-colors">Participants</div>
          <div class="text-sm text-base-content/50">Manage race entrants</div>
        </div>
        <.icon name="hero-chevron-right" class="size-5 ml-auto text-base-content/30 group-hover:text-primary/60 transition-colors" />
      </.link>

      <.link
        navigate={~p"/admin/races/#{@race.id}/timing"}
        class="group flex items-center gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm hover:border-secondary/40 hover:shadow-md transition-all"
      >
        <div class="rounded-lg bg-secondary/10 p-3">
          <.icon name="hero-clock" class="size-6 text-secondary" />
        </div>
        <div>
          <div class="font-semibold text-base-content group-hover:text-secondary transition-colors">Timing</div>
          <div class="text-sm text-base-content/50">Race day console</div>
        </div>
        <.icon name="hero-chevron-right" class="size-5 ml-auto text-base-content/30 group-hover:text-secondary/60 transition-colors" />
      </.link>
    </div>

    <%!-- Categories Section --%>
    <div class="mt-10">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-tag" class="size-5 text-base-content/40" />
        <h2 class="text-lg font-semibold text-base-content">Categories</h2>
      </div>

      <div :if={@race.categories != []} class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm">
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">Name</th>
              <th class="font-semibold">Distance</th>
              <th class="font-semibold">Gender</th>
              <th class="font-semibold">Age Range</th>
              <th class="font-semibold">Order</th>
              <th class="font-semibold"><span class="sr-only">Actions</span></th>
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
              <td class="py-3 text-sm text-base-content/70">{format_age_range(cat.min_age, cat.max_age)}</td>
              <td class="py-3 text-sm text-base-content/70">{cat.sort_order}</td>
              <td class="py-3">
                <button
                  phx-click="delete_category"
                  phx-value-id={cat.id}
                  data-confirm="Are you sure you want to delete this category?"
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@race.categories == []} class="text-sm text-base-content/50 mb-4 italic">
        No categories yet. Add one below.
      </p>

      <%!-- Add Category Form --%>
      <div class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" />
          Add Category
        </h3>
        <.form for={@category_form} phx-submit="add_category" class="flex flex-wrap gap-3 items-end">
          <.input field={@category_form[:name]} type="text" label="Name" required placeholder="e.g. Elite Men" />
          <.input field={@category_form[:distance_label]} type="text" label="Distance" placeholder="e.g. 5K" />
          <.input
            field={@category_form[:gender]}
            type="select"
            label="Gender"
            options={[{"Any", :any}, {"Male", :male}, {"Female", :female}]}
          />
          <.input field={@category_form[:min_age]} type="number" label="Min Age" />
          <.input field={@category_form[:max_age]} type="number" label="Max Age" />
          <.input field={@category_form[:sort_order]} type="number" label="Order" value="0" />
          <.button type="submit" variant="primary">Add</.button>
        </.form>
      </div>
    </div>

    <%!-- Splits Section --%>
    <div class="mt-10">
      <div class="flex items-center gap-2 mb-4">
        <.icon name="hero-scissors" class="size-5 text-base-content/40" />
        <h2 class="text-lg font-semibold text-base-content">Splits</h2>
      </div>

      <div :if={@race.splits != []} class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm">
        <table class="table w-full">
          <thead>
            <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
              <th class="font-semibold">Name</th>
              <th class="font-semibold">Short Name</th>
              <th class="font-semibold">Leg Type</th>
              <th class="font-semibold">Distance (m)</th>
              <th class="font-semibold">Order</th>
              <th class="font-semibold"><span class="sr-only">Actions</span></th>
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
                  data-confirm="Are you sure you want to delete this split?"
                  class="text-sm font-medium text-error/70 hover:text-error transition-colors"
                >
                  Delete
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p :if={@race.splits == []} class="text-sm text-base-content/50 mb-4 italic">
        No splits yet. Add one below.
      </p>

      <%!-- Add Split Form --%>
      <div class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/30 p-5">
        <h3 class="text-sm font-semibold text-base-content/70 mb-4 flex items-center gap-1.5">
          <.icon name="hero-plus-circle" class="size-4 text-primary/60" />
          Add Split
        </h3>
        <.form for={@split_form} phx-submit="add_split" class="flex flex-wrap gap-3 items-end">
          <.input field={@split_form[:name]} type="text" label="Name" required placeholder="e.g. Swim" />
          <.input field={@split_form[:short_name]} type="text" label="Short Name" required placeholder="e.g. S1" />
          <.input
            field={@split_form[:leg_type]}
            type="select"
            label="Leg Type"
            options={[
              {"Swim", :swim},
              {"Bike", :bike},
              {"Run", :run},
              {"Transition", :transition},
              {"Other", :other}
            ]}
            required
          />
          <.input field={@split_form[:distance_meters]} type="number" label="Distance (m)" />
          <.input field={@split_form[:sort_order]} type="number" label="Order" value="0" />
          <.button type="submit" variant="primary">Add</.button>
        </.form>
      </div>
    </div>

    <div class="mt-10 pt-4 border-t border-base-200">
      <.link navigate={~p"/admin/races"} class="text-sm text-base-content/50 hover:text-primary transition-colors flex items-center gap-1">
        <.icon name="hero-arrow-left" class="size-3.5" /> Back to races
      </.link>
    </div>
    """
  end

  @impl true
  def handle_event("add_category", %{"race_category" => category_params}, socket) do
    category_params = Map.put(category_params, "race_id", socket.assigns.race.id)

    case Races.create_category(category_params) do
      {:ok, _category} ->
        race = Races.get_race!(socket.assigns.race.id)

        {:noreply,
         socket
         |> assign(:race, race)
         |> assign_category_form(Races.change_category(%RaceCategory{}))
         |> put_flash(:info, "Category added.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_category_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Races.get_category!(id)
    {:ok, _} = Races.delete_category(category)
    race = Races.get_race!(socket.assigns.race.id)

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, "Category deleted.")}
  end

  @impl true
  def handle_event("add_split", %{"split" => split_params}, socket) do
    split_params = Map.put(split_params, "race_id", socket.assigns.race.id)

    case Races.create_split(split_params) do
      {:ok, _split} ->
        race = Races.get_race!(socket.assigns.race.id)

        {:noreply,
         socket
         |> assign(:race, race)
         |> assign_split_form(Races.change_split(%Split{}))
         |> put_flash(:info, "Split added.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_split_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("delete_split", %{"id" => id}, socket) do
    split = Races.get_split!(id)
    {:ok, _} = Races.delete_split(split)
    race = Races.get_race!(socket.assigns.race.id)

    {:noreply,
     socket
     |> assign(:race, race)
     |> put_flash(:info, "Split deleted.")}
  end

  defp assign_category_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :category_form, to_form(changeset))
  end

  defp assign_split_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :split_form, to_form(changeset))
  end

  defp format_age_range(nil, nil), do: "Any"
  defp format_age_range(min, nil), do: "#{min}+"
  defp format_age_range(nil, max), do: "Up to #{max}"
  defp format_age_range(min, max), do: "#{min}-#{max}"

  defp status_pill_class(status) do
    case status do
      :draft -> "bg-base-content/10 text-base-content/60"
      :registration_open -> "bg-info/15 text-info"
      :registration_closed -> "bg-warning/15 text-warning"
      :in_progress -> "bg-success/15 text-success"
      :finished -> "bg-accent/15 text-accent"
      :archived -> "bg-neutral/15 text-neutral"
      _ -> "bg-base-content/10 text-base-content/60"
    end
  end

  defp format_status(status) do
    status
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
