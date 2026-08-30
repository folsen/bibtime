defmodule Bibtime.Results.AccoladesTest do
  use ExUnit.Case, async: true

  alias Bibtime.Participants.Participant
  alias Bibtime.Results.Accolades
  alias Bibtime.Results.ParticipantResult

  defp split(id, leg_type), do: %{id: id, leg_type: leg_type}

  defp result(name, gender, status, leg_times, total_ms) do
    %ParticipantResult{
      participant: %Participant{
        first_name: name,
        last_name: "Runner",
        bib_number: name,
        gender: gender
      },
      status: status,
      leg_times: leg_times,
      total_ms: total_ms
    }
  end

  # Bob swims fastest, Alice runs fastest and wins overall.
  defp sample do
    splits = [split(1, :swim), split(2, :bike), split(3, :run)]

    results = [
      result("alice", :female, :finished, %{1 => 300, 2 => 600, 3 => 400}, 1300),
      result("bob", :male, :finished, %{1 => 200, 2 => 700, 3 => 500}, 1400),
      result("cara", :female, :finished, %{1 => 400, 2 => 500, 3 => 600}, 1500)
    ]

    {results, splits}
  end

  describe "compute/2" do
    test "names the fastest athlete on each timed leg" do
      {results, splits} = sample()

      by_label = Map.new(Accolades.compute(results, splits), &{&1.label, &1})

      assert by_label[:fastest_swim].participant.first_name == "bob"
      assert by_label[:fastest_bike].participant.first_name == "cara"
      assert by_label[:fastest_run].participant.first_name == "alice"
    end

    test "names the fastest woman and man overall" do
      {results, splits} = sample()

      by_label = Map.new(Accolades.compute(results, splits), &{&1.label, &1})

      assert by_label[:fastest_woman].participant.first_name == "alice"
      assert by_label[:fastest_man].participant.first_name == "bob"
    end

    test "formats the time on the card" do
      {results, splits} = sample()

      swim = Enum.find(Accolades.compute(results, splits), &(&1.label == :fastest_swim))

      assert swim.detail == Bibtime.Results.Calculator.format_time(200)
    end

    test "ignores anyone who did not finish, however quick their leg" do
      {results, splits} = sample()
      flyer = result("dana", :female, :dnf, %{1 => 1, 2 => 1, 3 => 1}, nil)

      by_label = Map.new(Accolades.compute([flyer | results], splits), &{&1.label, &1})

      assert by_label[:fastest_swim].participant.first_name == "bob"
      refute Enum.any?(Map.values(by_label), &(&1.participant.first_name == "dana"))
    end

    test "skips legs nobody has a time for" do
      splits = [split(1, :swim), split(2, :bike), split(3, :run)]
      results = [result("alice", :female, :finished, %{1 => 300}, 300)]

      labels = Accolades.compute(results, splits) |> Enum.map(& &1.label)

      assert :fastest_swim in labels
      refute :fastest_bike in labels
      refute :fastest_run in labels
    end

    test "skips a gender nobody finished in" do
      splits = [split(1, :swim)]
      results = [result("alice", :female, :finished, %{1 => 300}, 300)]

      labels = Accolades.compute(results, splits) |> Enum.map(& &1.label)

      assert :fastest_woman in labels
      refute :fastest_man in labels
    end

    test "returns nothing when nobody has finished" do
      {results, splits} = sample()
      unfinished = Enum.map(results, &%{&1 | status: :racing})

      assert Accolades.compute(unfinished, splits) == []
      assert Accolades.compute([], splits) == []
    end

    test "only considers legs that are swim, bike or run" do
      splits = [split(1, :swim), split(2, :transition), split(3, :other)]
      results = [result("alice", :female, :finished, %{1 => 300, 2 => 10, 3 => 20}, 330)]

      labels = Accolades.compute(results, splits) |> Enum.map(& &1.label)

      assert labels == [:fastest_swim, :fastest_woman]
    end
  end

  describe "fastest_leg_times/2" do
    test "agrees with the accolade cards" do
      {results, splits} = sample()

      assert Accolades.fastest_leg_times(results, splits) == %{1 => 200, 2 => 500, 3 => 400}
    end

    test "ignores unfinished athletes, matching compute/2" do
      {results, splits} = sample()
      flyer = result("dana", :female, :dnf, %{1 => 1}, nil)

      assert Accolades.fastest_leg_times([flyer | results], splits)[1] == 200
    end

    test "omits legs with no times" do
      splits = [split(1, :swim), split(2, :bike)]
      results = [result("alice", :female, :finished, %{1 => 300}, 300)]

      assert Accolades.fastest_leg_times(results, splits) == %{1 => 300}
    end
  end

  describe "fastest_total_ms/1" do
    test "returns the winning time" do
      {results, _splits} = sample()

      assert Accolades.fastest_total_ms(results) == 1300
    end

    test "is nil when nobody has finished" do
      assert Accolades.fastest_total_ms([]) == nil
      assert Accolades.fastest_total_ms([result("a", :male, :racing, %{}, nil)]) == nil
    end
  end
end
