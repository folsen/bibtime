defmodule Bibtime.Timing.StationAssignmentTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Timing

  import Bibtime.RacesFixtures
  import Bibtime.TimingFixtures

  describe "assign_station/2" do
    test "assigns a station to several splits of the same race" do
      {_race, [_swim, bike, run]} = triathlon_fixture()
      station = station_fixture()

      assert {:ok, _} = Timing.assign_station(station, bike)
      assert {:ok, _} = Timing.assign_station(station, run)

      assert [first, second] = Timing.list_assigned_splits(station.id)
      assert first.id == bike.id
      assert second.id == run.id
    end

    test "rejects splits from a different race than existing assignments" do
      {_race_a, [swim_a | _]} = triathlon_fixture()
      {_race_b, [swim_b | _]} = triathlon_fixture()

      station = station_fixture() |> assign_station!(swim_a)

      assert {:error, :different_race} = Timing.assign_station(station, swim_b)
    end

    test "rejects a second station on an already covered split" do
      {_race, [swim | _]} = triathlon_fixture()

      _first = station_fixture(%{"name" => "One"}) |> assign_station!(swim)
      second = station_fixture(%{"name" => "Two"})

      assert {:error, %Ecto.Changeset{}} = Timing.assign_station(second, swim)
    end

    test "rejects assigning the same split to the same station twice" do
      {_race, [swim | _]} = triathlon_fixture()
      station = station_fixture() |> assign_station!(swim)

      assert {:error, %Ecto.Changeset{}} = Timing.assign_station(station, swim)
    end
  end

  describe "unassign_station/2" do
    test "removes only the given split's assignment" do
      {_race, [_swim, bike, run]} = triathlon_fixture()
      station = station_fixture() |> assign_station!(bike) |> assign_station!(run)

      assert :ok = Timing.unassign_station(station, bike)

      assert [remaining] = Timing.list_assigned_splits(station.id)
      assert remaining.id == run.id
    end
  end

  describe "delete_timing_station/1" do
    test "removes the station along with its assignments" do
      {race, [swim | _]} = triathlon_fixture()
      station = station_fixture() |> assign_station!(swim)

      assert {:ok, _} = Timing.delete_timing_station(station)

      assert Timing.list_stations_for_race(race.id) == []
      assert Timing.list_assigned_splits(station.id) == []
    end
  end

  describe "list_stations_for_race/1" do
    test "returns a multi-assigned station once with ordered assignments" do
      {race, [_swim, bike, run]} = triathlon_fixture()
      station = station_fixture() |> assign_station!(run) |> assign_station!(bike)

      assert [found] = Timing.list_stations_for_race(race.id)
      assert found.id == station.id

      assert [a1, a2] = found.split_assignments
      assert a1.split.id == bike.id
      assert a2.split.id == run.id
    end
  end
end
