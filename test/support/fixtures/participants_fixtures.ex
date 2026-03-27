defmodule Bibtime.ParticipantsFixtures do
  @moduledoc """
  Test helpers for creating participant entities.
  """

  alias Bibtime.Participants

  def participant_fixture(race, attrs \\ %{}) do
    {:ok, participant} =
      attrs
      |> Enum.into(%{
        bib_number: "#{System.unique_integer([:positive])}",
        first_name: "Test",
        last_name: "Runner",
        race_id: race.id
      })
      |> Participants.create_participant()

    participant
  end
end
