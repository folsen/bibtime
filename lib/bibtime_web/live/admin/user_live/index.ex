defmodule BibtimeWeb.Admin.UserLive.Index do
  use BibtimeWeb, :live_view

  alias Bibtime.Accounts
  alias Bibtime.AuditLog

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    admin_count = Accounts.count_admins()

    {:ok,
     socket
     |> assign(:all_users, users)
     |> assign(:admin_count, admin_count)
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> assign_paginated(users)}
  end

  defp assign_paginated(socket, all_users) do
    total = length(all_users)

    socket
    |> assign(:total_count, total)
    |> assign(:total_pages, max(1, ceil(total / @page_size)))
    |> paginate(all_users)
  end

  defp paginate(socket, all_users) do
    page = socket.assigns.page
    page_items = all_users |> Enum.drop((page - 1) * @page_size) |> Enum.take(@page_size)
    assign(socket, :users, page_items)
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    page = String.to_integer(page)
    {:noreply, socket |> assign(:page, page) |> paginate(socket.assigns.all_users)}
  end

  @impl true
  def handle_event("change_role", %{"user-id" => user_id, "role" => new_role}, socket) do
    current_user = socket.assigns.current_scope.user
    target_user = Accounts.get_user!(user_id)

    cond do
      target_user.id == current_user.id ->
        {:noreply, put_flash(socket, :error, gettext("You cannot change your own role."))}

      target_user.role == "admin" and new_role != "admin" and socket.assigns.admin_count <= 1 ->
        {:noreply, put_flash(socket, :error, gettext("Cannot remove the last admin."))}

      true ->
        old_role = target_user.role

        case Accounts.update_user_role(target_user, new_role) do
          {:ok, _user} ->
            AuditLog.log(current_user, "user.role_changed", "user", target_user.id, %{
              "email" => target_user.email,
              "old_role" => old_role,
              "new_role" => new_role
            })

            users = Accounts.list_users()

            {:noreply,
             socket
             |> assign(:all_users, users)
             |> assign(:admin_count, Accounts.count_admins())
             |> assign_paginated(users)
             |> put_flash(:info, gettext("User role updated successfully."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to update user role."))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 pb-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Users")}
        </h1>
        <p class="mt-1 text-sm text-base-content/60">
          {gettext("Manage user accounts and roles.")}
        </p>
      </div>
    </div>

    <%!-- Pagination top --%>
    <.pagination
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <div
      :if={@users != []}
      class="overflow-x-auto rounded-xl border border-base-300 bg-base-100 shadow-sm"
    >
      <table class="table w-full">
        <thead>
          <tr class="border-b border-base-300 bg-base-200/40 text-xs uppercase tracking-wider text-base-content/50">
            <th class="font-semibold">{gettext("Email")}</th>
            <th class="font-semibold">{gettext("Role")}</th>
            <th class="font-semibold">{gettext("Joined")}</th>
            <th class="font-semibold"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={user <- @users}
            id={"user-#{user.id}"}
            class="border-b border-base-200 odd:bg-base-100 even:bg-base-200/30 hover:bg-primary/5 transition-colors"
          >
            <td class="py-3">
              <span class="font-medium text-base-content">{user.email}</span>
              <span
                :if={user.id == @current_scope.user.id}
                class="ml-2 text-xs text-base-content/40"
              >
                ({gettext("you")})
              </span>
            </td>
            <td class="py-3">
              <span class={[
                "rounded-full px-2.5 py-0.5 text-xs font-medium",
                role_pill_class(user.role)
              ]}>
                {format_user_role(user.role)}
              </span>
            </td>
            <td class="py-3 text-sm text-base-content/70">
              {format_date_short(user.inserted_at)}
            </td>
            <td class="py-3">
              <div :if={user.id != @current_scope.user.id} class="flex items-center gap-2">
                <button
                  :for={role <- ~w(admin timer user)}
                  :if={user.role != role}
                  phx-click="change_role"
                  phx-value-user-id={user.id}
                  phx-value-role={role}
                  class="text-xs font-medium text-primary hover:text-primary/80 transition-colors"
                >
                  {role_action_label(role)}
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <%!-- Pagination bottom --%>
    <.pagination
      page={@page}
      total_pages={@total_pages}
      total_count={@total_count}
      page_size={@page_size}
    />

    <div
      :if={@users == [] and @all_users == []}
      class="flex flex-col items-center justify-center py-16 text-center"
    >
      <div class="rounded-full bg-primary/10 p-4 mb-4">
        <.icon name="hero-users" class="size-10 text-primary/40" />
      </div>
      <h3 class="text-lg font-semibold text-base-content/80 mb-1">
        {gettext("No users found")}
      </h3>
    </div>
    """
  end

  defp role_pill_class("admin"), do: "bg-primary/15 text-primary"
  defp role_pill_class("timer"), do: "bg-info/15 text-info"
  defp role_pill_class("user"), do: "bg-base-content/10 text-base-content/60"
  defp role_pill_class(_), do: "bg-base-content/10 text-base-content/60"

  defp role_action_label("admin"), do: gettext("Set Admin")
  defp role_action_label("timer"), do: gettext("Set Timer")
  defp role_action_label("user"), do: gettext("Set User")
  defp role_action_label(_), do: ""
end
