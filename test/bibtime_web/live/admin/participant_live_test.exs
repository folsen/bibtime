defmodule BibtimeWeb.Admin.ParticipantLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PaymentsFixtures

  alias Bibtime.AuditLog.AuditLogEntry
  alias Bibtime.Participants
  alias Bibtime.Payments.Payment
  alias Bibtime.Repo

  describe "Index — remove participant" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      race = race_fixture()
      %{conn: log_in_user(conn, admin), race: race}
    end

    test "removes the participant and shows a flash", %{conn: conn, race: race} do
      participant =
        participant_fixture(race, %{first_name: "Anjali", last_name: "Haryana"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/participants")

      assert render_async(view) =~ "Anjali"

      html =
        view
        |> element(~s(button[phx-click="remove"][phx-value-id="#{participant.id}"]))
        |> render_click()

      assert html =~ "Removed Anjali Haryana from the race."
      refute html =~ ~s(phx-value-id="#{participant.id}")
      assert Repo.get(Participants.Participant, participant.id) == nil
    end

    test "cascades associated payment records", %{conn: conn, race: race} do
      participant = participant_fixture(race)
      payment = payment_fixture(participant, race)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/participants")
      render_async(view)

      view
      |> element(~s(button[phx-click="remove"][phx-value-id="#{participant.id}"]))
      |> render_click()

      assert Repo.get(Payment, payment.id) == nil
    end

    test "writes an audit log entry with identifying metadata", %{conn: conn, race: race} do
      participant =
        participant_fixture(race, %{first_name: "Gone", last_name: "Runner"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/participants")
      render_async(view)

      view
      |> element(~s(button[phx-click="remove"][phx-value-id="#{participant.id}"]))
      |> render_click()

      entry =
        Repo.one(
          from e in AuditLogEntry,
            where: e.action == "participant.deleted" and e.resource_id == ^participant.id
        )

      assert entry
      assert entry.metadata["name"] == "Gone Runner"
      assert entry.metadata["race_id"] == race.id
    end

    test "does not remove a participant belonging to another race", %{conn: conn, race: race} do
      other_race = race_fixture(%{name: "Other Race"})
      other_participant = participant_fixture(other_race)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/participants")
      render_async(view)

      render_click(view, "remove", %{"id" => to_string(other_participant.id)})

      assert Repo.get(Participants.Participant, other_participant.id)
    end
  end
end
