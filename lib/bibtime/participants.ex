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
    |> order_by([p], asc: fragment("LENGTH(?)", p.bib_number), asc: p.bib_number)
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
  Checks in a participant by assigning a chip_id and setting status to :checked_in.

  Broadcasts `{:participant_checked_in, participant}` on `"race:checkin:<race_id>"`.
  """
  def check_in_participant(%Participant{} = participant, chip_id) do
    participant
    |> Participant.changeset(%{
      chip_id: chip_id,
      checked_in_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: :checked_in
    })
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(
          Bibtime.PubSub,
          "race:checkin:#{updated.race_id}",
          {:participant_checked_in, updated}
        )

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Unchecks a participant by clearing chip_id and checked_in_at, reverting status to :registered.

  Broadcasts `{:participant_unchecked, participant}` on `"race:checkin:<race_id>"`.
  """
  def uncheck_in_participant(%Participant{} = participant) do
    participant
    |> Participant.changeset(%{chip_id: nil, checked_in_at: nil, status: :registered})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(
          Bibtime.PubSub,
          "race:checkin:#{updated.race_id}",
          {:participant_unchecked, updated}
        )

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns the count of checked-in participants for a race.
  """
  def count_checked_in_participants(race_id) do
    Participant
    |> where([p], p.race_id == ^race_id and not is_nil(p.checked_in_at))
    |> Repo.aggregate(:count)
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
  Returns the count of "slots taken" in a race: registered participants plus
  pending-payment participants whose hold has not yet expired. This is the
  number that `Registration.registration_full?/1` checks against the race's
  `participant_limit`.

  A participant row without a hold and without being registered (e.g. a
  previous-attempt pending row whose hold lapsed) doesn't count — the
  slot is free to take again.
  """
  def count_slots_taken(race_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Participant
    |> where([p], p.race_id == ^race_id)
    |> where(
      [p],
      not is_nil(p.bib_number) or
        (p.status == :pending_payment and p.hold_expires_at > ^now)
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns a user's pending-payment participants whose hold is still valid,
  preloaded with `:race`. Used to render a global "finish payment" banner
  for logged-in users with an in-flight registration.
  """
  def list_active_pending_for_user(nil), do: []

  def list_active_pending_for_user(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Participant
    |> where(
      [p],
      p.user_id == ^user_id and p.status == :pending_payment and p.hold_expires_at > ^now
    )
    |> preload(:race)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
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
  Returns true if the user is registered as a participant in the given race.
  """
  def user_participant_in_race?(nil, _race_id), do: false

  def user_participant_in_race?(user_id, race_id) do
    Participant
    |> where([p], p.user_id == ^user_id and p.race_id == ^race_id)
    |> Repo.exists?()
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

  @doc """
  Returns all participant entries linked to a user for the given race.
  Preloads `:race_category`, ordered by bib_number.
  """
  def list_user_participants_in_race(nil, _race_id), do: []

  def list_user_participants_in_race(user_id, race_id) do
    Participant
    |> where([p], p.user_id == ^user_id and p.race_id == ^race_id)
    |> preload(:race_category)
    |> order_by([p], p.bib_number)
    |> Repo.all()
  end

  @doc """
  Finds an existing participant in `race_id` whose (first_name, last_name, email)
  matches the given values after trim + downcase normalization. Returns the
  participant or nil.

  Intended as an anti-duplicate-registration check — a logged-in user or a
  distracted re-submit of the same form would produce exact matches we want
  to block, while still letting the same email register *different* people
  (e.g. a spouse).
  """
  def find_duplicate_registration(race_id, first_name, last_name, email) do
    target_first = normalize_registration_field(first_name)
    target_last = normalize_registration_field(last_name)
    target_email = normalize_registration_field(email)

    if target_first == "" or target_email == "" do
      nil
    else
      Participant
      |> where([p], p.race_id == ^race_id)
      |> Repo.all()
      |> Enum.find(fn p ->
        normalize_registration_field(p.first_name) == target_first and
          normalize_registration_field(p.last_name) == target_last and
          normalize_registration_field(p.email) == target_email
      end)
    end
  end

  defp normalize_registration_field(nil), do: ""

  defp normalize_registration_field(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end
end
