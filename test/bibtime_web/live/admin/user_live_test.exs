defmodule BibtimeWeb.Admin.UserLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures

  describe "Index (non-admin)" do
    setup :register_and_log_in_user

    test "redirects non-admin users", %{conn: conn} do
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end
  end

  describe "Index (admin)" do
    setup :register_and_log_in_admin_user

    test "lists all users", %{conn: conn, user: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ admin.email
      assert html =~ "Admin"
    end

    test "shows role pills for each user", %{conn: conn} do
      _timer = timer_user_fixture()
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Timer"
    end

    test "can promote a user to admin", %{conn: conn} do
      regular_user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      html =
        render_click(view, "change_role", %{
          "user-id" => "#{regular_user.id}",
          "role" => "admin"
        })

      assert html =~ "User role updated successfully"
      updated = Bibtime.Accounts.get_user!(regular_user.id)
      assert updated.role == "admin"
    end

    test "can change a user to timer role", %{conn: conn} do
      regular_user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "change_role", %{
        "user-id" => "#{regular_user.id}",
        "role" => "timer"
      })

      updated = Bibtime.Accounts.get_user!(regular_user.id)
      assert updated.role == "timer"
    end

    test "can demote a user back to regular user", %{conn: conn} do
      admin2 = admin_user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "change_role", %{
        "user-id" => "#{admin2.id}",
        "role" => "user"
      })

      updated = Bibtime.Accounts.get_user!(admin2.id)
      assert updated.role == "user"
    end

    test "cannot change own role", %{conn: conn, user: admin} do
      {:ok, view, html} = live(conn, ~p"/admin/users")

      # The current user should show "(you)" marker
      assert html =~ "(you)"

      html =
        render_click(view, "change_role", %{
          "user-id" => "#{admin.id}",
          "role" => "user"
        })

      assert html =~ "cannot change your own role"
    end

    test "can demote admin when multiple admins exist", %{conn: conn} do
      other = admin_user_fixture()
      assert Bibtime.Accounts.count_admins() == 2

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "change_role", %{
        "user-id" => "#{other.id}",
        "role" => "user"
      })

      assert Bibtime.Accounts.count_admins() == 1
      assert Bibtime.Accounts.get_user!(other.id).role == "user"
    end

    test "creates an audit log entry on role change", %{conn: conn} do
      regular_user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "change_role", %{
        "user-id" => "#{regular_user.id}",
        "role" => "admin"
      })

      [entry | _] = Bibtime.AuditLog.list_entries()
      assert entry.action == "user.role_changed"
      assert entry.resource_type == "user"
      assert entry.resource_id == regular_user.id
      assert entry.metadata["old_role"] == "user"
      assert entry.metadata["new_role"] == "admin"
    end
  end

  describe "Timer user access" do
    test "timer users cannot access /admin/users", %{conn: conn} do
      timer = timer_user_fixture()
      conn = log_in_user(conn, timer)
      conn = get(conn, ~p"/admin/users")
      assert redirected_to(conn) == "/"
    end
  end
end
