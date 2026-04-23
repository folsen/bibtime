defmodule Bibtime.ParticipantsTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Participants
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.Race

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race! do
    Repo.insert!(%Race{
      name: "Test Race",
      slug: "test-race-#{System.unique_integer([:positive])}",
      race_type: :running,
      status: :draft
    })
  end

  defp create_participant!(race, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          bib_number: "#{System.unique_integer([:positive])}",
          first_name: "Jane",
          last_name: "Doe",
          race_id: race.id
        },
        overrides
      )

    {:ok, participant} = Participants.create_participant(attrs)
    participant
  end

  defp link_user(%Participant{} = participant, user) do
    participant
    |> Ecto.Changeset.change(%{user_id: user.id})
    |> Repo.update!()
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "create_participant/1" do
    test "with valid attrs succeeds" do
      race = create_race!()

      assert {:ok, %Participant{} = p} =
               Participants.create_participant(%{
                 bib_number: "101",
                 first_name: "Alice",
                 last_name: "Smith",
                 race_id: race.id
               })

      assert p.bib_number == "101"
      assert p.first_name == "Alice"
      assert p.status == :registered
    end

    test "with duplicate bib number in same race fails" do
      race = create_race!()
      create_participant!(race, %{bib_number: "101"})

      assert {:error, changeset} =
               Participants.create_participant(%{
                 bib_number: "101",
                 first_name: "Bob",
                 last_name: "Jones",
                 race_id: race.id
               })

      assert %{race_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "duplicate bib number in different race succeeds" do
      race1 = create_race!()
      race2 = create_race!()
      create_participant!(race1, %{bib_number: "101"})

      assert {:ok, _} =
               Participants.create_participant(%{
                 bib_number: "101",
                 first_name: "Bob",
                 last_name: "Jones",
                 race_id: race2.id
               })
    end
  end

  describe "list_participants/1" do
    test "returns participants for a race ordered by bib_number" do
      race = create_race!()
      create_participant!(race, %{bib_number: "3", first_name: "Third"})
      create_participant!(race, %{bib_number: "1", first_name: "First"})
      create_participant!(race, %{bib_number: "2", first_name: "Second"})

      participants = Participants.list_participants(race.id)
      assert length(participants) == 3
      assert Enum.map(participants, & &1.bib_number) == ["1", "2", "3"]
    end

    test "sorts numeric bib_numbers numerically, not lexicographically" do
      race = create_race!()

      for bib <- ~w(1 2 3 10 11 20 100) do
        create_participant!(race, %{bib_number: bib})
      end

      assert Enum.map(Participants.list_participants(race.id), & &1.bib_number) ==
               ~w(1 2 3 10 11 20 100)
    end

    test "does not return participants from other races" do
      race1 = create_race!()
      race2 = create_race!()
      create_participant!(race1, %{bib_number: "1"})
      create_participant!(race2, %{bib_number: "2"})

      assert length(Participants.list_participants(race1.id)) == 1
    end
  end

  describe "get_participant_by_bib/2" do
    test "returns participant by race_id and bib_number" do
      race = create_race!()
      p = create_participant!(race, %{bib_number: "42"})

      found = Participants.get_participant_by_bib(race.id, "42")
      assert found.id == p.id
    end

    test "returns nil when not found" do
      race = create_race!()
      assert Participants.get_participant_by_bib(race.id, "999") == nil
    end
  end

  describe "get_participant_by_chip/2" do
    test "returns participant by race_id and chip_id" do
      race = create_race!()
      p = create_participant!(race, %{bib_number: "10", chip_id: "CHIP-ABC"})

      found = Participants.get_participant_by_chip(race.id, "CHIP-ABC")
      assert found.id == p.id
    end

    test "returns nil when not found" do
      race = create_race!()
      assert Participants.get_participant_by_chip(race.id, "NO-CHIP") == nil
    end
  end

  describe "status transitions" do
    test "mark_dns/1 sets status to :dns" do
      race = create_race!()
      p = create_participant!(race)
      assert {:ok, updated} = Participants.mark_dns(p)
      assert updated.status == :dns
    end

    test "mark_dnf/1 sets status to :dnf" do
      race = create_race!()
      p = create_participant!(race)
      assert {:ok, updated} = Participants.mark_dnf(p)
      assert updated.status == :dnf
    end

    test "mark_dsq/1 sets status to :dsq" do
      race = create_race!()
      p = create_participant!(race)
      assert {:ok, updated} = Participants.mark_dsq(p)
      assert updated.status == :dsq
    end

    test "mark_finished/1 sets status to :finished" do
      race = create_race!()
      p = create_participant!(race)
      assert {:ok, updated} = Participants.mark_finished(p)
      assert updated.status == :finished
    end
  end

  describe "list_user_participants_in_race/2" do
    test "returns [] for nil user" do
      race = create_race!()
      assert Participants.list_user_participants_in_race(nil, race.id) == []
    end

    test "returns only the given user's participants in the race, ordered by bib" do
      race = create_race!()
      other_race = create_race!()

      {:ok, user} = Bibtime.Accounts.register_user(%{email: "u@example.com"})
      {:ok, other_user} = Bibtime.Accounts.register_user(%{email: "o@example.com"})

      p1 = link_user(create_participant!(race, %{bib_number: "2"}), user)
      p2 = link_user(create_participant!(race, %{bib_number: "1"}), user)
      _other = link_user(create_participant!(race), other_user)
      _different_race = link_user(create_participant!(other_race), user)

      results = Participants.list_user_participants_in_race(user.id, race.id)
      assert Enum.map(results, & &1.id) == [p2.id, p1.id]
    end
  end

  describe "find_duplicate_registration/4" do
    test "matches exact (case/whitespace insensitive) same-race entry" do
      race = create_race!()

      existing =
        create_participant!(race, %{
          first_name: "Alice",
          last_name: "Smith",
          email: "alice@example.com"
        })

      match =
        Participants.find_duplicate_registration(
          race.id,
          " ALICE ",
          "smith",
          "Alice@Example.COM"
        )

      assert match && match.id == existing.id
    end

    test "returns nil when name differs" do
      race = create_race!()

      _existing =
        create_participant!(race, %{
          first_name: "Alice",
          last_name: "Smith",
          email: "alice@example.com"
        })

      refute Participants.find_duplicate_registration(
               race.id,
               "Bob",
               "Smith",
               "alice@example.com"
             )
    end

    test "returns nil when in a different race" do
      race1 = create_race!()
      race2 = create_race!()

      _existing =
        create_participant!(race1, %{
          first_name: "Alice",
          last_name: "Smith",
          email: "alice@example.com"
        })

      refute Participants.find_duplicate_registration(
               race2.id,
               "Alice",
               "Smith",
               "alice@example.com"
             )
    end

    test "returns nil when email or first_name is blank" do
      race = create_race!()
      refute Participants.find_duplicate_registration(race.id, nil, "x", "a@b.com")
      refute Participants.find_duplicate_registration(race.id, "x", "y", nil)
    end
  end
end
