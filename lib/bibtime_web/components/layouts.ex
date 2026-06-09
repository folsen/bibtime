defmodule BibtimeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BibtimeWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  @doc """
  Compact "you have a pending payment" banner for logged-in users with an
  in-flight paid registration. Rendered globally from the root layout so a
  user who bails on Stripe and lands on any page (home, my-races, profile)
  has a one-click path back to finish.
  """
  attr :current_scope, :map, default: nil

  def pending_payment_banner(%{current_scope: %{user: %{id: id}}} = assigns)
      when not is_nil(id) do
    pending = Bibtime.Participants.list_active_pending_for_user(id)
    assigns = Phoenix.Component.assign(assigns, :pending, pending)

    ~H"""
    <div :if={@pending != []} class="bg-warning/10 border-b border-warning/30">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-2 flex flex-wrap items-center gap-3 text-sm">
        <.icon name="hero-clock" class="size-4 text-warning shrink-0" />
        <span class="text-base-content/80 flex-1 min-w-0">
          <%= if length(@pending) == 1 do %>
            {gettext(
              "You have a pending payment for %{race} — finish payment to save your spot.",
              race: hd(@pending).race.name
            )}
          <% else %>
            {gettext("You have %{count} pending payments — finish them to save your spots.",
              count: length(@pending)
            )}
          <% end %>
        </span>
        <a
          :for={p <- @pending}
          href={~p"/races/#{p.race.slug}/register/confirmation/#{p.confirmation_token}"}
          class="btn btn-warning btn-xs gap-1 shrink-0"
        >
          {if length(@pending) == 1, do: gettext("Finish payment"), else: p.race.name}
          <.icon name="hero-arrow-right" class="size-3" />
        </a>
      </div>
    </div>
    """
  end

  def pending_payment_banner(assigns), do: ~H""

  @doc """
  Subtle footer with "Powered by BibTime" link and optional organizer contact.

  Rendered globally by root.html.heex (skipped by the kiosk root layout).
  """
  attr :site_settings, :map, required: true

  def powered_by_footer(assigns) do
    ~H"""
    <footer class="border-t border-base-300 bg-base-200/40">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex flex-wrap items-center justify-between gap-4 text-xs text-base-content/40">
        <span>
          {gettext("Powered by")}
          <a
            href="https://bibtime.io"
            target="_blank"
            rel="noopener"
            class="hover:text-primary transition-colors"
          >
            BibTime
          </a>
        </span>
        <div
          :if={@site_settings.organizer_email || @site_settings.organizer_website}
          class="flex items-center gap-4"
        >
          <a
            :if={@site_settings.organizer_email}
            href={"mailto:#{@site_settings.organizer_email}"}
            class="hover:text-primary transition-colors"
          >
            {@site_settings.organizer_email}
          </a>
          <a
            :if={@site_settings.organizer_website}
            href={@site_settings.organizer_website}
            target="_blank"
            rel="noopener"
            class="hover:text-primary transition-colors"
          >
            {display_website(@site_settings.organizer_website)}
          </a>
        </div>
      </div>
    </footer>
    """
  end

  defp display_website(url) do
    url
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
    |> String.trim_trailing("/")
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
