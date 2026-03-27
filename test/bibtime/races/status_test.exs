defmodule Bibtime.Races.StatusTest do
  use Bibtime.DataCase, async: true

  import Bibtime.RacesFixtures

  alias Bibtime.Races

  @valid_statuses [
    :draft,
    :registration_open,
    :registration_closed,
    :in_progress,
    :finished,
    :archived
  ]

  describe "race status via changeset" do
    test "all valid statuses are accepted" do
      for status <- @valid_statuses do
        race = race_fixture(%{status: :draft})
        assert {:ok, updated} = Races.update_race(race, %{status: status})
        assert updated.status == status
      end
    end

    test "invalid status is rejected" do
      race = race_fixture()

      assert {:error, changeset} =
               Races.update_race(race, %{status: :nonexistent_status})

      assert %{status: [_msg]} = errors_on(changeset)
    end

    test "all forward transitions are possible" do
      transitions = [
        {:draft, :registration_open},
        {:registration_open, :registration_closed},
        {:registration_closed, :in_progress},
        {:in_progress, :finished},
        {:finished, :archived}
      ]

      for {from, to} <- transitions do
        race = race_fixture(%{status: from})
        assert {:ok, updated} = Races.update_race(race, %{status: to})
        assert updated.status == to
      end
    end

    test "backward transitions are also accepted (no guard)" do
      race = race_fixture(%{status: :finished})
      assert {:ok, updated} = Races.update_race(race, %{status: :in_progress})
      assert updated.status == :in_progress
    end
  end

  describe "participant auto-status via timing" do
    import Bibtime.ParticipantsFixtures
    import Bibtime.TimingFixtures

    test "recording first split transitions participant from registered to racing" do
      {race, [swim, _bike, _run]} = triathlon_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      assert participant.status == :registered

      record_split_time!(participant, swim, 100_000)

      updated = Bibtime.Participants.get_participant!(participant.id)
      assert updated.status == :racing
    end

    test "recording all splits transitions participant to finished" do
      {race, [swim, bike, run]} = triathlon_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      record_split_time!(participant, swim, 100_000)
      record_split_time!(participant, bike, 400_000)
      record_split_time!(participant, run, 900_000)

      updated = Bibtime.Participants.get_participant!(participant.id)
      assert updated.status == :finished
    end

    test "recording split time does not override manual DNS status" do
      {race, [swim, _bike, _run]} = triathlon_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      {:ok, dns_participant} = Bibtime.Participants.mark_dns(participant)
      assert dns_participant.status == :dns

      record_split_time!(dns_participant, swim, 100_000)

      updated = Bibtime.Participants.get_participant!(participant.id)
      assert updated.status == :dns
    end

    test "recording split time does not override manual DNF status" do
      {race, [swim, _bike, _run]} = triathlon_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      {:ok, dnf_participant} = Bibtime.Participants.mark_dnf(participant)
      record_split_time!(dnf_participant, swim, 100_000)

      updated = Bibtime.Participants.get_participant!(participant.id)
      assert updated.status == :dnf
    end

    test "recording split time does not override manual DSQ status" do
      {race, [swim, _bike, _run]} = triathlon_fixture()
      participant = participant_fixture(race, %{bib_number: "1"})

      {:ok, dsq_participant} = Bibtime.Participants.mark_dsq(participant)
      record_split_time!(dsq_participant, swim, 100_000)

      updated = Bibtime.Participants.get_participant!(participant.id)
      assert updated.status == :dsq
    end
  end
end
