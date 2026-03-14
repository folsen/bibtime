defmodule Bibtime.Timing do
  @moduledoc """
  The Timing context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Timing.SplitTime
  alias Bibtime.Timing.RaceStart
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.Split

  # ---------------------------------------------------------------------------
  # SplitTime
  # ---------------------------------------------------------------------------

  @doc """
  Records a split time for a participant.

  Broadcasts a `{:split_time_recorded, split_time}` message on the
  `"race:timing:<race_id>"` PubSub topic.
  """
  def record_split_time(attrs) do
    %SplitTime{}
    |> SplitTime.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, split_time} ->
        race_id = get_race_id_for_participant(split_time.participant_id)
        update_participant_status(split_time.participant_id, race_id)

        Phoenix.PubSub.broadcast(
          Bibtime.PubSub,
          "race:timing:#{race_id}",
          {:split_time_recorded, split_time}
        )

        {:ok, split_time}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets a single split time.

  Raises `Ecto.NoResultsError` if the SplitTime does not exist.
  """
  def get_split_time!(id), do: Repo.get!(SplitTime, id)

  @doc """
  Deletes a split time.

  Broadcasts a `{:split_time_deleted, split_time}` message on the
  `"race:timing:<race_id>"` PubSub topic.
  """
  def delete_split_time(%SplitTime{} = split_time) do
    race_id = get_race_id_for_participant(split_time.participant_id)

    case Repo.delete(split_time) do
      {:ok, split_time} ->
        update_participant_status(split_time.participant_id, race_id)

        Phoenix.PubSub.broadcast(
          Bibtime.PubSub,
          "race:timing:#{race_id}",
          {:split_time_deleted, split_time}
        )

        {:ok, split_time}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns all split times for participants in the given race.

  Preloads `:participant` and `:split`.
  """
  def get_split_times_for_race(race_id) do
    SplitTime
    |> join(:inner, [st], p in Participant, on: st.participant_id == p.id)
    |> where([_st, p], p.race_id == ^race_id)
    |> preload([:participant, :split])
    |> Repo.all()
  end

  @doc """
  Returns all split times for the given participant, ordered by the split's
  `sort_order`.

  Preloads `:split`.
  """
  def get_split_times_for_participant(participant_id) do
    SplitTime
    |> where([st], st.participant_id == ^participant_id)
    |> join(:inner, [st], s in assoc(st, :split))
    |> order_by([_st, s], asc: s.sort_order)
    |> preload(:split)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # RaceStart
  # ---------------------------------------------------------------------------

  @doc """
  Creates a race start record.
  """
  def start_race(attrs) do
    %RaceStart{}
    |> RaceStart.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the race start for the given race.

  If multiple race starts exist, returns the earliest one (by `started_at`).
  Returns `nil` if no race start is found.
  """
  def get_race_start(race_id) do
    RaceStart
    |> where([rs], rs.race_id == ^race_id)
    |> order_by([rs], asc: rs.started_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Lists all race starts for a given race, ordered by `started_at`.
  """
  def list_race_starts(race_id) do
    RaceStart
    |> where([rs], rs.race_id == ^race_id)
    |> order_by([rs], asc: rs.started_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Derives the correct status from split-time counts and updates the
  # participant record when the status should change. Only transitions
  # between the timing-driven statuses (:registered, :racing, :finished).
  # Manual overrides (dns/dnf/dsq) are never touched.
  defp update_participant_status(participant_id, race_id) do
    participant = Repo.get!(Participant, participant_id)

    # Don't override manual statuses
    if participant.status in [:dns, :dnf, :dsq] do
      :ok
    else
      total_splits = Split |> where([s], s.race_id == ^race_id) |> Repo.aggregate(:count)
      recorded = SplitTime |> where([st], st.participant_id == ^participant_id) |> Repo.aggregate(:count)

      new_status =
        cond do
          total_splits > 0 and recorded >= total_splits -> :finished
          recorded > 0 -> :racing
          true -> :registered
        end

      if participant.status != new_status do
        Bibtime.Participants.update_participant(participant, %{status: new_status})
      end
    end
  end

  defp get_race_id_for_participant(participant_id) do
    Participant
    |> where([p], p.id == ^participant_id)
    |> select([p], p.race_id)
    |> Repo.one!()
  end
end
