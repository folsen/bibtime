defmodule BibtimeWeb.Admin.SettingsLive.Edit do
  use BibtimeWeb, :live_view

  alias Bibtime.SiteSettings
  alias Bibtime.Races
  alias Bibtime.AuditLog

  @impl true
  def mount(_params, _session, socket) do
    settings = SiteSettings.get()
    changeset = SiteSettings.change(settings)
    locales = BibtimeWeb.Plugs.SetLocale.supported_locales()

    {:ok,
     socket
     |> assign(:page_title, gettext("Site Settings"))
     |> assign(:settings, settings)
     |> assign(:locales, locales)
     |> assign(:active_locale, hd(locales))
     |> assign(:races, Races.list_races())
     |> assign_form(changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-6">
      <h1 class="text-2xl font-semibold tracking-tight text-base-content">
        {gettext("Site Settings")}
      </h1>
      <p class="mt-1 text-sm text-base-content/60">
        {gettext("Customize the site name, landing page, and call-to-action.")}
      </p>
    </div>

    <div class="max-w-3xl">
      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-8">
        <%!-- Site Name --%>
        <section class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
          <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider">
            {gettext("Branding")}
          </h2>
          <.input
            field={@form[:site_name]}
            type="text"
            label={gettext("Site name")}
            required
            phx-debounce="300"
          />
          <p class="text-xs text-base-content/40">
            {gettext("Shown in the top-left header and as the page title suffix.")}
          </p>
        </section>

        <%!-- Hero Section (translatable) --%>
        <section class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
          <div class="flex items-center justify-between gap-4">
            <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider">
              {gettext("Landing page hero")}
            </h2>
            <.locale_tabs active={@active_locale} locales={@locales} />
          </div>

          <div
            :for={locale <- @locales}
            class={if locale == @active_locale, do: "space-y-4", else: "hidden"}
          >
            <.input
              name={"site_settings[hero_title][#{locale}]"}
              value={translation_value(@form, :hero_title, locale)}
              type="text"
              label={gettext("Hero title (%{locale})", locale: String.upcase(locale))}
              phx-debounce="300"
            />
            <.input
              name={"site_settings[hero_subtitle][#{locale}]"}
              value={translation_value(@form, :hero_subtitle, locale)}
              type="textarea"
              label={gettext("Hero subtitle (%{locale})", locale: String.upcase(locale))}
              rows="3"
              phx-debounce="300"
            />
          </div>
          <p class="text-xs text-base-content/40">
            {gettext("Leave both languages empty to use the built-in defaults.")}
          </p>
        </section>

        <%!-- Call to Action --%>
        <section class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
          <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider">
            {gettext("Call to action")}
          </h2>

          <.input
            field={@form[:cta_mode]}
            type="select"
            label={gettext("CTA mode")}
            options={cta_mode_options()}
          />

          <%= case Phoenix.HTML.Form.input_value(@form, :cta_mode) do %>
            <% "featured_race" -> %>
              <.input
                field={@form[:featured_race_id]}
                type="select"
                label={gettext("Featured race")}
                options={race_options(@races)}
                prompt={gettext("Select a race")}
              />
              <p class="text-xs text-base-content/40">
                {gettext(
                  "Link goes to the race registration page when registration is open, otherwise to the race detail page."
                )}
              </p>
              <div class="flex items-center justify-between gap-4 pt-2">
                <p class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                  {gettext("Button label override (optional)")}
                </p>
                <.locale_tabs active={@active_locale} locales={@locales} />
              </div>
              <div
                :for={locale <- @locales}
                class={if locale == @active_locale, do: "block", else: "hidden"}
              >
                <.input
                  name={"site_settings[cta_label][#{locale}]"}
                  value={translation_value(@form, :cta_label, locale)}
                  type="text"
                  label={gettext("Label (%{locale})", locale: String.upcase(locale))}
                  placeholder={gettext("Defaults to the race name")}
                  phx-debounce="300"
                />
              </div>
            <% "custom" -> %>
              <.input
                field={@form[:cta_url]}
                type="text"
                label={gettext("URL")}
                placeholder="https://example.com/register"
                phx-debounce="300"
              />
              <div class="flex items-center justify-between gap-4 pt-2">
                <p class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                  {gettext("Button label")}
                </p>
                <.locale_tabs active={@active_locale} locales={@locales} />
              </div>
              <div
                :for={locale <- @locales}
                class={if locale == @active_locale, do: "block", else: "hidden"}
              >
                <.input
                  name={"site_settings[cta_label][#{locale}]"}
                  value={translation_value(@form, :cta_label, locale)}
                  type="text"
                  label={gettext("Label (%{locale})", locale: String.upcase(locale))}
                  phx-debounce="300"
                />
              </div>
            <% _ -> %>
              <p class="text-xs text-base-content/40">
                {gettext("Default: shows a Log in button to visitors who are not logged in.")}
              </p>
          <% end %>
        </section>

        <%!-- Organizer Contact --%>
        <section class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm space-y-4">
          <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wider">
            {gettext("Organizer contact (optional)")}
          </h2>
          <p class="text-xs text-base-content/40">
            {gettext("Shown subtly in the site footer.")}
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:organizer_email]}
              type="email"
              label={gettext("Email")}
              placeholder="info@example.com"
              phx-debounce="300"
            />
            <.input
              field={@form[:organizer_website]}
              type="text"
              label={gettext("Website")}
              placeholder="https://example.com"
              phx-debounce="300"
            />
          </div>
        </section>

        <div class="flex items-center gap-4">
          <.button type="submit" variant="primary">
            <.icon name="hero-check" class="size-4 mr-1" /> {gettext("Save Settings")}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"site_settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> SiteSettings.change(normalize_params(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"site_settings" => params}, socket) do
    case SiteSettings.update(normalize_params(params)) do
      {:ok, settings} ->
        AuditLog.log(
          socket.assigns.current_scope.user,
          "site_settings.updated",
          "site_settings",
          settings.id
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Site settings updated."))
         |> assign(:settings, settings)
         |> assign(:site_settings, settings)
         |> assign_form(SiteSettings.change(settings))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("set_locale", %{"locale" => locale}, socket) do
    if locale in socket.assigns.locales do
      {:noreply, assign(socket, :active_locale, locale)}
    else
      {:noreply, socket}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: "site_settings"))
  end

  # Empty strings from form inputs are stripped during changeset normalization,
  # but we also need to make sure that unchecked/unsent locale fields don't
  # wipe previously saved values. We achieve this by merging the submitted
  # translation params over the current settings on the changeset side.
  defp normalize_params(params) do
    params
  end

  defp translation_value(form, field, locale) do
    case Phoenix.HTML.Form.input_value(form, field) do
      %{} = map -> Map.get(map, locale, "")
      _ -> ""
    end
  end

  defp cta_mode_options do
    [
      {gettext("Default (Log in button)"), "default"},
      {gettext("Featured race"), "featured_race"},
      {gettext("Custom URL"), "custom"}
    ]
  end

  defp race_options(races) do
    Enum.map(races, fn race -> {race.name, race.id} end)
  end

  attr :active, :string, required: true
  attr :locales, :list, required: true

  defp locale_tabs(assigns) do
    ~H"""
    <div class="inline-flex items-center rounded-lg border border-base-300 bg-base-200/60 p-0.5 text-xs">
      <button
        :for={locale <- @locales}
        type="button"
        phx-click="set_locale"
        phx-value-locale={locale}
        class={[
          "px-3 py-1 rounded-md font-semibold transition-colors",
          if(locale == @active,
            do: "bg-base-100 text-primary shadow-sm",
            else: "text-base-content/50 hover:text-base-content"
          )
        ]}
      >
        {String.upcase(locale)}
      </button>
    </div>
    """
  end
end
