defmodule Bibtime.Participants do
  @moduledoc """
  The Participants context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Participants.Participant

  @doc """
  Returns the list of participants for a given race, ordered by bib_number.
  Preloads the race_category association.
  """
  def list_participants(race_id) do
    Participant
    |> where([p], p.race_id == ^race_id)
    |> order_by([p], p.bib_number)
    |> preload(:race_category)
    |> Repo.all()
  end

  @doc """
  Gets a single participant.

  Raises `Ecto.NoResultsError` if the Participant does not exist.
  """
  def get_participant!(id), do: Repo.get!(Participant, id)

  @doc """
  Gets a participant by race_id and bib_number.

  Returns nil if no participant is found.
  """
  def get_participant_by_bib(race_id, bib_number) do
    Repo.get_by(Participant, race_id: race_id, bib_number: bib_number)
  end

  @doc """
  Gets a participant by race_id and chip_id.

  Returns nil if no participant is found.
  """
  def get_participant_by_chip(race_id, chip_id) do
    Repo.get_by(Participant, race_id: race_id, chip_id: chip_id)
  end

  @doc """
  Creates a participant.
  """
  def create_participant(attrs \\ %{}) do
    %Participant{}
    |> Participant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a participant.
  """
  def update_participant(%Participant{} = participant, attrs) do
    participant
    |> Participant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a participant.
  """
  def delete_participant(%Participant{} = participant) do
    Repo.delete(participant)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking participant changes.
  """
  def change_participant(%Participant{} = participant, attrs \\ %{}) do
    Participant.changeset(participant, attrs)
  end

  @doc """
  Marks a participant as DNS (Did Not Start).
  """
  def mark_dns(%Participant{} = participant) do
    update_participant(participant, %{status: :dns})
  end

  @doc """
  Marks a participant as DNF (Did Not Finish).
  """
  def mark_dnf(%Participant{} = participant) do
    update_participant(participant, %{status: :dnf})
  end

  @doc """
  Marks a participant as DSQ (Disqualified).
  """
  def mark_dsq(%Participant{} = participant) do
    update_participant(participant, %{status: :dsq})
  end

  @doc """
  Marks a participant as finished.
  """
  def mark_finished(%Participant{} = participant) do
    update_participant(participant, %{status: :finished})
  end

  @doc """
  Returns the next available bib number for a race.
  Finds the max numeric bib and adds 1.
  """
  def next_bib_number(race_id) do
    max =
      Participant
      |> where([p], p.race_id == ^race_id)
      |> select([p], max(fragment("CAST(? AS INTEGER)", p.bib_number)))
      |> Repo.one() || 0

    Integer.to_string(max + 1)
  end

  @doc """
  Returns the count of participants for a race.
  """
  def count_participants(race_id) do
    Participant
    |> where([p], p.race_id == ^race_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a participant by confirmation token.
  """
  def get_participant_by_token(token) do
    Repo.get_by(Participant, confirmation_token: token)
    |> Repo.preload(:race_category)
  end

  @doc """
  Returns all participant entries for a user, preloaded with race and category.
  """
  def list_participants_for_user(user_id) do
    Participant
    |> where([p], p.user_id == ^user_id)
    |> preload([:race_category, :race])
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the most recent participant record for a user, or nil.

  Used to pre-fill registration forms with data from past races.
  """
  def get_latest_participant_for_user(user_id) do
    Participant
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
