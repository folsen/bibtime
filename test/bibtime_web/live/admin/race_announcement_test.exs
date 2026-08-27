defmodule BibtimeWeb.Admin.RaceAnnouncementTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures

  alias Bibtime.Accounts.User
  alias Bibtime.Repo

  @body "The Start PM is published: https://example.com/start-pm.pdf"

  setup %{conn: conn} do
    admin = admin_user_fixture()
    race = race_fixture(%{name: "Klagshamn Triathlon"})
    # The admin fixture logs in by magic link, which mails the test process.
    flush_emails()
    %{conn: log_in_user(conn, admin), race: race, admin: admin}
  end

  defp with_email(participant, email) do
    user = Repo.insert!(%User{email: email})

    participant
    |> Ecto.Changeset.change(user_id: user.id)
    |> Repo.update!()
  end

  # deliver_many reaches the test process as one {:emails, list} message.
  defp sent_emails(acc \\ []) do
    receive do
      {:emails, emails} -> sent_emails(acc ++ emails)
      {:email, email} -> sent_emails(acc ++ [email])
    after
      0 -> acc
    end
  end

  defp flush_emails, do: sent_emails()

  # The send runs on the task supervisor and reports back by message, which is
  # outside what render_async/1 knows how to wait for.
  defp render_until(view, text, attempts \\ 40) do
    html = render(view)

    cond do
      html =~ text -> html
      attempts == 0 -> flunk("timed out waiting for #{inspect(text)}")
      true -> Process.sleep(25) && render_until(view, text, attempts - 1)
    end
  end

  defp fill(view, params) do
    view
    |> form("form[phx-submit='send_announcement']", announcement: params)
    |> render_change()
  end

  test "shows how many participants will be reached", %{conn: conn, race: race} do
    with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")
    with_email(participant_fixture(race, %{bib_number: "2"}), "two@example.com")
    # No user account, so no address.
    participant_fixture(race, %{bib_number: "3"})

    {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}")

    assert html =~ "2 participants will receive this"
    assert html =~ "1 has no email address and will be skipped"
  end

  test "recounts when unpaid registrations are included", %{conn: conn, race: race} do
    with_email(participant_fixture(race, %{bib_number: "1"}), "paid@example.com")

    with_email(
      participant_fixture(race, %{bib_number: "2", status: :pending_payment}),
      "unpaid@example.com"
    )

    {:ok, view, html} = live(conn, ~p"/admin/races/#{race.id}")
    assert html =~ "1 participant will receive this"

    html =
      fill(view, %{"subject" => "Hi", "body" => @body, "include_pending_payment" => "true"})

    assert html =~ "2 participants will receive this"
  end

  test "sends the announcement and reports the result", %{conn: conn, race: race} do
    with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")
    with_email(participant_fixture(race, %{bib_number: "2"}), "two@example.com")

    {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}")

    fill(view, %{"subject" => "Start PM", "body" => @body})

    view
    |> form("form[phx-submit='send_announcement']",
      announcement: %{"subject" => "Start PM", "body" => @body}
    )
    |> render_submit()

    render_until(view, "Announcement sent to 2 participants.")

    emails = sent_emails()
    assert length(emails) == 2
    assert Enum.all?(emails, &(&1.subject == "Start PM"))
  end

  test "refuses to send without a subject and body", %{conn: conn, race: race} do
    with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")

    {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}")

    html =
      view
      |> form("form[phx-submit='send_announcement']",
        announcement: %{"subject" => "  ", "body" => ""}
      )
      |> render_submit()

    assert html =~ "Add a subject and a message before sending."
    assert sent_emails() == []
  end

  test "sends a test copy to the admin only", %{conn: conn, race: race, admin: admin} do
    with_email(participant_fixture(race, %{bib_number: "1"}), "runner@example.com")

    {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}")

    fill(view, %{"subject" => "Start PM", "body" => @body})

    html =
      view
      |> element("button[phx-click='send_test_announcement']")
      |> render_click()

    assert html =~ "Test email sent to #{admin.email}"

    assert [email] = sent_emails()
    assert email.to == [{"", admin.email}]
    refute "runner@example.com" in Enum.map(email.to, fn {_n, addr} -> addr end)
  end

  test "is not reachable by a non-admin", %{race: race} do
    conn = log_in_user(build_conn(), user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/races/#{race.id}")
  end
end
