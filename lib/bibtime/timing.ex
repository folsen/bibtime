defmodule Bibtime.Timing do
  @moduledoc """
  The Timing context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Timing.SplitTime
  alias Bibtime.Timing.RaceStart
  alias Bibtime.Timing.TimingStation
  alias Bibtime.Participants
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
  #
  # A participant is :finished once they have a recorded time for the final
  # split (by sort_order) — middle splits like transitions may be missing.
  defp update_participant_status(participant_id, race_id) do
    participant = Repo.get!(Participant, participant_id)

    if participant.status in [:dns, :dnf, :dsq] do
      :ok
    else
      final_split_id =
        Split
        |> where([s], s.race_id == ^race_id)
        |> order_by([s], desc: s.sort_order)
        |> limit(1)
        |> select([s], s.id)
        |> Repo.one()

      recorded =
        SplitTime |> where([st], st.participant_id == ^participant_id) |> Repo.aggregate(:count)

      has_final_time? =
        final_split_id != nil and
          Repo.exists?(
            from st in SplitTime,
              where: st.participant_id == ^participant_id and st.split_id == ^final_split_id
          )

      new_status =
        cond do
          has_final_time? -> :finished
          recorded > 0 -> :racing
          participant.status == :checked_in -> :checked_in
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

  # ---------------------------------------------------------------------------
  # TimingStation
  # ---------------------------------------------------------------------------

  @doc """
  Creates a timing station (app-level, not tied to a specific race).

  If the attrs do not include a `:token` (or `"token"`), a cryptographically
  strong random token is generated.
  """
  def create_timing_station(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put_new_lazy("token", &generate_station_token/0)

    %TimingStation{}
    |> TimingStation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a timing station by its token. Returns `nil` if not found.
  """
  def get_station_by_token(nil), do: nil

  def get_station_by_token(token) when is_binary(token) do
    Repo.get_by(TimingStation, token: token)
  end

  @doc """
  Gets a timing station by id, raising if not found.
  """
  def get_timing_station!(id), do: Repo.get!(TimingStation, id)

  @doc """
  Updates a station's heartbeat information. Merges any supplied metadata
  into the station's existing metadata map, sets `last_seen_at`, updates
  `firmware_version` and `status` if provided.

  Broadcasts on the race-specific topic if the station is currently assigned.
  """
  def update_station_heartbeat(%TimingStation{} = station, metadata) when is_map(metadata) do
    metadata = stringify_keys(metadata)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {firmware_version, metadata} = Map.pop(metadata, "firmware_version")
    {status_override, metadata} = Map.pop(metadata, "status")

    merged = Map.merge(station.metadata || %{}, metadata)

    status =
      case status_override do
        nil ->
          # Derive status from reader_connected when no explicit override
          case Map.get(metadata, "reader_connected") do
            false -> :error
            _ -> :online
          end

        status when is_atom(status) ->
          status

        status when is_binary(status) ->
          safe_station_status(status)
      end

    attrs =
      %{
        last_seen_at: now,
        status: status,
        metadata: merged
      }
      |> maybe_put(:firmware_version, firmware_version)

    result =
      station
      |> TimingStation.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        race_id = get_race_id_for_station(updated)

        if race_id do
          Phoenix.PubSub.broadcast(
            Bibtime.PubSub,
            "race:stations:#{race_id}",
            {:station_heartbeat, updated.id, updated.metadata}
          )
        end

        {:ok, updated}

      other ->
        other
    end
  end

  @doc """
  Lists all timing stations, preloading their assigned split (and the split's
  race).
  """
  def list_all_stations do
    TimingStation
    |> order_by([s], asc: s.inserted_at)
    |> preload(assigned_split: :race)
    |> Repo.all()
  end

  @doc """
  Lists timing stations currently assigned to splits belonging to the given
  race, preloaded with their assigned split.
  """
  def list_stations_for_race(race_id) do
    TimingStation
    |> join(:inner, [ts], s in Split, on: ts.assigned_split_id == s.id)
    |> where([_ts, s], s.race_id == ^race_id)
    |> order_by([ts, _s], asc: ts.inserted_at)
    |> preload(:assigned_split)
    |> Repo.all()
  end

  @doc """
  Assigns a timing station to a split. Unassigns any previous assignment.
  """
  def assign_station(%TimingStation{} = station, %Split{} = split) do
    station
    |> TimingStation.changeset(%{assigned_split_id: split.id})
    |> Repo.update()
  end

  @doc """
  Removes the current split assignment from a timing station.
  """
  def unassign_station(%TimingStation{} = station) do
    station
    |> TimingStation.changeset(%{assigned_split_id: nil})
    |> Repo.update()
  end

  @doc """
  Deletes a timing station.
  """
  def delete_timing_station(%TimingStation{} = station) do
    Repo.delete(station)
  end

  defp generate_station_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64()
  end

  defp safe_station_status(str) do
    case str do
      "offline" -> :offline
      "online" -> :online
      "reading" -> :reading
      "error" -> :error
      _ -> :online
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp get_race_id_for_station(%TimingStation{assigned_split_id: nil}), do: nil

  defp get_race_id_for_station(%TimingStation{assigned_split_id: split_id}) do
    Split
    |> where([s], s.id == ^split_id)
    |> select([s], s.race_id)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Chip-read ingestion
  # ---------------------------------------------------------------------------

  @doc """
  Ingests a single raw chip read coming from a `TimingStation`.

  Returns one of:
    * `{:ok, :recorded, participant, split_time}` — read saved as a split time
    * `{:ok, :duplicate, participant}` — participant already has a split time
      recorded for this station's split
    * `{:ok, :unmatched}` — chip_id is not assigned to any participant in the
      station's race
    * `{:error, :station_unassigned}` — station is not assigned to a split
    * `{:error, :race_not_started}` — no race start has been configured yet
    * `{:error, reason}` — any other error (e.g. changeset validation error)

  Broadcasts `{:station_read, station_id, payload}` on
  `"race:stations:<race_id>"` for recorded and unmatched reads (but not for
  duplicates).
  """
  def ingest_chip_read(%TimingStation{assigned_split_id: nil}, _raw) do
    {:error, :station_unassigned}
  end

  def ingest_chip_read(%TimingStation{} = station, %{"chip_id" => chip_id} = raw) do
    race_id = get_race_id_for_station(station)
    split_id = station.assigned_split_id

    case Participants.get_participant_by_chip(race_id, chip_id) do
      nil ->
        broadcast_station_read(race_id, station.id, %{
          status: :unmatched,
          chip_id: chip_id
        })

        {:ok, :unmatched}

      %Participant{} = participant ->
        if split_time_exists?(participant.id, split_id) do
          {:ok, :duplicate, participant}
        else
          do_ingest(station, participant, raw)
        end
    end
  end

  defp do_ingest(%TimingStation{} = station, %Participant{} = participant, raw) do
    race_id = get_race_id_for_station(station)
    split_id = station.assigned_split_id

    with {:ok, read_at} <- parse_read_at(Map.get(raw, "read_at")),
         %RaceStart{} = race_start <- get_race_start(race_id),
         elapsed_ms <- DateTime.diff(read_at, race_start.started_at, :millisecond),
         {:ok, split_time} <-
           record_split_time(%{
             participant_id: participant.id,
             split_id: split_id,
             absolute_time: read_at,
             elapsed_ms: elapsed_ms,
             source: :chip,
             raw_chip_data: Jason.encode!(raw)
           }) do
      broadcast_station_read(race_id, station.id, %{
        status: :recorded,
        chip_id: Map.get(raw, "chip_id"),
        participant_id: participant.id,
        bib_number: participant.bib_number,
        split_id: split_id,
        elapsed_ms: elapsed_ms
      })

      {:ok, :recorded, participant, split_time}
    else
      nil -> {:error, :race_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_time_exists?(participant_id, split_id) do
    SplitTime
    |> where([st], st.participant_id == ^participant_id and st.split_id == ^split_id)
    |> Repo.exists?()
  end

  defp parse_read_at(nil), do: {:ok, DateTime.utc_now()}
  defp parse_read_at(%DateTime{} = dt), do: {:ok, dt}

  defp parse_read_at(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, :invalid_read_at}
    end
  end

  defp parse_read_at(_), do: {:error, :invalid_read_at}

  defp broadcast_station_read(race_id, station_id, payload) do
    Phoenix.PubSub.broadcast(
      Bibtime.PubSub,
      "race:stations:#{race_id}",
      {:station_read, station_id, payload}
    )
  end
end
