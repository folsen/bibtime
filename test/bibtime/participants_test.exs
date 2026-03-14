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
end
