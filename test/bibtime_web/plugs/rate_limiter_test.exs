defmodule BibtimeWeb.Plugs.RateLimiterTest do
  use BibtimeWeb.ConnCase

  import Bibtime.AccountsFixtures

  describe "rate limiting on POST /users/log-in" do
    test "allows login attempts under the limit", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end

    test "blocks login after 5 attempts from the same IP", %{conn: conn} do
      user = user_fixture()

      # Use up 5 allowed attempts
      for _ <- 1..5 do
        conn
        |> recycle()
        |> post(~p"/users/log-in", %{"user" => %{"email" => user.email}})
      end

      # 6th attempt should be rate-limited
      conn =
        conn
        |> recycle()
        |> post(~p"/users/log-in", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == "/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many login attempts"
    end

    test "tracks different IPs independently", %{conn: conn} do
      user = user_fixture()

      # Exhaust rate limit for IP 10.0.0.1
      for _ <- 1..6 do
        %{conn | remote_ip: {10, 0, 0, 1}}
        |> recycle()
        |> post(~p"/users/log-in", %{"user" => %{"email" => user.email}})
      end

      # Different IP should still work
      allowed_conn =
        %{conn | remote_ip: {10, 0, 0, 2}}
        |> recycle()
        |> post(~p"/users/log-in", %{"user" => %{"email" => user.email}})

      assert redirected_to(allowed_conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(allowed_conn.assigns.flash, :info) =~
               "If your email is in our system"
    end

    test "does not rate-limit GET requests", %{conn: conn} do
      # Exhaust POST rate limit
      for _ <- 1..6 do
        conn
        |> recycle()
        |> post(~p"/users/log-in", %{"user" => %{"email" => "test@example.com"}})
      end

      # GET should still work
      conn = get(conn, ~p"/users/log-in")
      assert html_response(conn, 200) =~ "Log in"
    end
  end
end
