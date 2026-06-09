defmodule BibtimeWeb.Public.MyRacesLive.EditTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures

  alias Bibtime.Participants

  # Links the participant to `user` by registering it with the user's email
  # (create_participant finds-or-links the user from the email).
  defp owned_participant(user, race, attrs) do
    participant_fixture(race, Map.merge(%{email: user.email}, attrs))
  end

  describe "access control" do
    test "a non-owner is redirected away", %{conn: conn} do
      owner = user_fixture()
      race = race_fixture(%{status: :registration_open})
      participant = owned_participant(owner, race, %{bib_number: "1"})

      conn = log_in_user(conn, user_fixture())

      assert {:error, {kind, %{to: "/my-races"}}} =
               live(conn, ~p"/my-races/#{participant.id}/edit")

      assert kind in [:redirect, :live_redirect]
    end
  end

  describe "editing as the owner" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "saves the allowed display fields", %{conn: conn, user: user} do
      race = race_fixture(%{status: :registration_open})
      participant = owned_participant(user, race, %{bib_number: "1", first_name: "Orig"})

      {:ok, view, _html} = live(conn, ~p"/my-races/#{participant.id}/edit")

      view
      |> form("#edit-registration-form", participant: %{first_name: "Updated", club: "ACME"})
      |> render_submit()

      updated = Participants.get_participant!(participant.id)
      assert updated.first_name == "Updated"
      assert updated.club == "ACME"
    end

    test "ignores privileged fields in a crafted submission", %{conn: conn, user: user} do
      race = race_fixture(%{status: :registration_open})

      participant =
        owned_participant(user, race, %{bib_number: "1", first_name: "Orig", status: :registered})

      {:ok, view, _html} = live(conn, ~p"/my-races/#{participant.id}/edit")

      # The form only renders the safe fields, so a real attacker would craft
      # the event payload directly — send "save" with privileged params and
      # confirm they're dropped server-side.
      render_submit(view, "save", %{
        "participant" => %{
          "first_name" => "Updated",
          "status" => "finished",
          "bib_number" => "999",
          "chip_id" => "HACKED"
        }
      })

      updated = Participants.get_participant!(participant.id)
      assert updated.first_name == "Updated"
      assert updated.status == :registered
      assert updated.bib_number == "1"
      assert updated.chip_id == nil
    end

    test "rejects edits once the race is no longer in a registration state",
         %{conn: conn, user: user} do
      race = race_fixture(%{status: :registration_open})
      participant = owned_participant(user, race, %{bib_number: "1", first_name: "Orig"})

      {:ok, view, _html} = live(conn, ~p"/my-races/#{participant.id}/edit")

      # Race transitions to in-progress while the edit form is open.
      Bibtime.Repo.update!(Ecto.Changeset.change(race, status: :in_progress))

      view
      |> form("#edit-registration-form", participant: %{first_name: "TooLate"})
      |> render_submit()

      assert Participants.get_participant!(participant.id).first_name == "Orig"
    end
  end
end
