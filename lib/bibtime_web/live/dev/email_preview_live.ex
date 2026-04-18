defmodule BibtimeWeb.Dev.EmailPreviewLive do
  use BibtimeWeb, :live_view

  alias Bibtime.Mailer.Previews

  @locales ~w(en sv)

  @impl true
  def mount(_params, _session, socket) do
    previews = Previews.all()
    first = List.first(previews)

    {:ok,
     socket
     |> assign(:page_title, "Email previews")
     |> assign(:previews, previews)
     |> assign(:locales, @locales)
     |> assign(:active_key, first && first.key)
     |> assign(:active_locale, "en")
     |> assign_rendered()}
  end

  @impl true
  def handle_event("select_preview", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:active_key, key) |> assign_rendered()}
  end

  @impl true
  def handle_event("select_locale", %{"locale" => locale}, socket) do
    if locale in @locales do
      {:noreply, socket |> assign(:active_locale, locale) |> assign_rendered()}
    else
      {:noreply, socket}
    end
  end

  defp assign_rendered(socket) do
    case Previews.find(socket.assigns.active_key) do
      nil ->
        assign(socket, :rendered, nil)

      preview ->
        email = preview.build.(socket.assigns.active_locale)
        assign(socket, :rendered, %{preview: preview, email: email})
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <div class="max-w-6xl">
        <div class="pb-6">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Email previews</h1>
          <p class="mt-1 text-sm text-base-content/60">
            Dev-only catalog of every notifier the app sends. Fixture data is hardcoded in <code class="text-xs">Bibtime.Mailer.Previews</code>.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-[16rem_1fr] gap-6">
          <nav class="flex flex-col gap-1">
            <button
              :for={preview <- @previews}
              type="button"
              phx-click="select_preview"
              phx-value-key={preview.key}
              class={[
                "text-left rounded-lg border px-3 py-2 transition-colors",
                if(preview.key == @active_key,
                  do: "border-primary bg-primary/5 text-base-content",
                  else:
                    "border-base-300 text-base-content/70 hover:border-base-300 hover:bg-base-200/60"
                )
              ]}
            >
              <div class="text-sm font-semibold">{preview.title}</div>
              <div class="text-xs text-base-content/50 mt-0.5">{preview.description}</div>
            </button>
          </nav>

          <div :if={@rendered} class="rounded-xl border border-base-300 bg-base-100 p-6 shadow-sm">
            <div class="flex items-center justify-between gap-4 pb-4 border-b border-base-200">
              <h2 class="text-lg font-semibold text-base-content">
                {@rendered.preview.title}
              </h2>
              <div class="inline-flex items-center rounded-lg border border-base-300 bg-base-200/60 p-0.5 text-xs">
                <button
                  :for={locale <- @locales}
                  type="button"
                  phx-click="select_locale"
                  phx-value-locale={locale}
                  class={[
                    "px-3 py-1 rounded-md font-semibold transition-colors",
                    if(locale == @active_locale,
                      do: "bg-base-100 text-primary shadow-sm",
                      else: "text-base-content/50 hover:text-base-content"
                    )
                  ]}
                >
                  {String.upcase(locale)}
                </button>
              </div>
            </div>

            <dl class="grid grid-cols-[6rem_1fr] gap-x-4 gap-y-2 pt-4 text-sm">
              <dt class="font-semibold text-base-content/60">From</dt>
              <dd class="font-mono text-xs">{format_address(@rendered.email.from)}</dd>
              <dt class="font-semibold text-base-content/60">To</dt>
              <dd class="font-mono text-xs">{format_addresses(@rendered.email.to)}</dd>
              <dt class="font-semibold text-base-content/60">Subject</dt>
              <dd class="font-semibold">{@rendered.email.subject}</dd>
            </dl>

            <div class="mt-6">
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-2">
                Text body
              </div>
              <pre class="whitespace-pre-wrap rounded-lg border border-base-200 bg-base-200/40 p-4 text-sm font-mono leading-6 text-base-content"><%= @rendered.email.text_body %></pre>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_address({nil, addr}), do: addr
  defp format_address({"", addr}), do: addr
  defp format_address({name, addr}), do: "\"#{name}\" <#{addr}>"
  defp format_address(addr) when is_binary(addr), do: addr
  defp format_address(nil), do: ""

  defp format_addresses(addresses) when is_list(addresses) do
    addresses |> Enum.map_join(", ", &format_address/1)
  end

  defp format_addresses(other), do: format_address(other)
end
