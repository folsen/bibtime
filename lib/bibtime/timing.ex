defmodule Bibtime.Timing do
  @moduledoc """
  The Timing context.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo

  alias Bibtime.Timing.SplitTime
  alias Bibtime.Timing.RaceStart
  alias Bibtime.Timing.TimingStation
  alias Bibtime.Timing.StationSplitAssignment
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

  @doc """
  Returns all split times flagged for review in the given race, newest first.

  Preloads `:participant` and `:split`.
  """
  def list_flagged_split_times(race_id) do
    SplitTime
    |> join(:inner, [st], p in Participant, on: st.participant_id == p.id)
    |> where([st, p], p.race_id == ^race_id and st.needs_review == true)
    |> order_by([st], desc: st.inserted_at)
    |> preload([:participant, :split])
    |> Repo.all()
  end

  @doc """
  Sets or clears the review flag on a split time.

  Broadcasts a `{:split_time_updated, split_time}` message on the
  `"race:timing:<race_id>"` PubSub topic.
  """
  def set_split_time_review(%SplitTime{} = split_time, needs_review)
      when is_boolean(needs_review) do
    race_id = get_race_id_for_participant(split_time.participant_id)

    split_time
    |> SplitTime.changeset(%{needs_review: needs_review})
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Phoenix.PubSub.broadcast(
          Bibtime.PubSub,
          "race:timing:#{race_id}",
          {:split_time_updated, updated}
        )

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
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
  Lists all timing stations, preloading their split assignments (with each
  split and its race), ordered by split `sort_order`.
  """
  def list_all_stations do
    TimingStation
    |> order_by([s], asc: s.inserted_at)
    |> preload(split_assignments: ^assignment_preload_query())
    |> Repo.all()
  end

  @doc """
  Lists timing stations currently assigned to at least one split of the given
  race, preloaded with their split assignments.
  """
  def list_stations_for_race(race_id) do
    TimingStation
    |> join(:inner, [ts], a in StationSplitAssignment, on: a.station_id == ts.id)
    |> join(:inner, [_ts, a], s in Split, on: a.split_id == s.id)
    |> where([_ts, _a, s], s.race_id == ^race_id)
    |> distinct(true)
    |> order_by([ts], asc: ts.inserted_at)
    |> preload(split_assignments: ^assignment_preload_query())
    |> Repo.all()
  end

  defp assignment_preload_query do
    StationSplitAssignment
    |> join(:inner, [a], s in assoc(a, :split))
    |> order_by([_a, s], asc: s.sort_order)
    |> preload([_a, s], split: {s, :race})
  end

  @doc """
  Lists the splits a station is assigned to, ordered by `sort_order`.
  """
  def list_assigned_splits(station_id) do
    Split
    |> join(:inner, [s], a in StationSplitAssignment, on: a.split_id == s.id)
    |> where([_s, a], a.station_id == ^station_id)
    |> order_by([s], asc: s.sort_order)
    |> Repo.all()
  end

  @doc """
  Assigns a timing station to a split, in addition to any existing
  assignments. All of a station's splits must belong to the same race.

  Returns `{:ok, assignment}`, `{:error, :different_race}` when the split
  belongs to another race than the station's existing assignments, or
  `{:error, changeset}` (e.g. when the split already has a station).
  """
  def assign_station(%TimingStation{} = station, %Split{} = split) do
    existing_race_id = get_race_id_for_station(station)

    if existing_race_id != nil and existing_race_id != split.race_id do
      {:error, :different_race}
    else
      %StationSplitAssignment{}
      |> StationSplitAssignment.changeset(%{station_id: station.id, split_id: split.id})
      |> Repo.insert()
    end
  end

  @doc """
  Removes the station's assignment to the given split. Other assignments of
  the same station are left untouched.
  """
  def unassign_station(%TimingStation{} = station, %Split{} = split) do
    StationSplitAssignment
    |> where([a], a.station_id == ^station.id and a.split_id == ^split.id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Updates station settings such as `pass_lockout_seconds`.
  """
  def update_station_settings(%TimingStation{} = station, attrs) do
    station
    |> TimingStation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a timing station along with its split assignments.
  """
  def delete_timing_station(%TimingStation{} = station) do
    Repo.transaction(fn ->
      StationSplitAssignment
      |> where([a], a.station_id == ^station.id)
      |> Repo.delete_all()

      case Repo.delete(station) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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

  # All of a station's splits belong to the same race (enforced by
  # assign_station/2), so any assignment determines the race.
  defp get_race_id_for_station(%TimingStation{id: station_id}) do
    StationSplitAssignment
    |> where([a], a.station_id == ^station_id)
    |> join(:inner, [a], s in assoc(a, :split))
    |> select([_a, s], s.race_id)
    |> limit(1)
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Chip-read ingestion
  # ---------------------------------------------------------------------------

  @outlier_min_samples 5
  @outlier_band 2

  @doc """
  Ingests a single raw chip read coming from a `TimingStation`.

  A station may be assigned to several splits of the same race. The read is
  credited to the lowest-`sort_order` assigned split the participant has no
  time for yet. Reads within `pass_lockout_seconds` of the participant's
  previous recorded time at this station count as re-reads of the same pass
  and are reported as duplicates.

  Returns one of:
    * `{:ok, :recorded, participant, split_time}` — read saved as a split time
      (`split_time.needs_review` marks suspicious multi-split attributions)
    * `{:ok, :duplicate, participant}` — the read is a re-read within the
      lockout window, or all of the station's splits are already recorded
    * `{:ok, :unmatched}` — chip_id is not assigned to any participant in the
      station's race
    * `{:error, :station_unassigned}` — station is not assigned to any split
    * `{:error, :race_not_started}` — no race start has been configured yet
    * `{:error, reason}` — any other error (e.g. changeset validation error)

  Broadcasts `{:station_read, station_id, payload}` on
  `"race:stations:<race_id>"` for recorded and unmatched reads (but not for
  duplicates).
  """
  def ingest_chip_read(%TimingStation{} = station, %{"chip_id" => chip_id} = raw) do
    case list_assigned_splits(station.id) do
      [] ->
        {:error, :station_unassigned}

      splits ->
        race_id = hd(splits).race_id

        case Participants.get_participant_by_chip(race_id, chip_id) do
          nil ->
            broadcast_station_read(race_id, station.id, %{
              status: :unmatched,
              chip_id: chip_id
            })

            {:ok, :unmatched}

          %Participant{} = participant ->
            do_ingest(station, splits, race_id, participant, raw)
        end
    end
  end

  defp do_ingest(%TimingStation{} = station, splits, race_id, %Participant{} = participant, raw) do
    with {:ok, read_at} <- parse_read_at(Map.get(raw, "read_at")) do
      existing = existing_split_entries(participant.id, race_id)
      chosen = choose_split(splits, existing)

      cond do
        locked_out?(existing, splits, read_at, station.pass_lockout_seconds) ->
          {:ok, :duplicate, participant}

        chosen == nil ->
          {:ok, :duplicate, participant}

        true ->
          record_chip_read(station, splits, race_id, participant, chosen, existing, read_at, raw)
      end
    end
  end

  defp record_chip_read(station, splits, race_id, participant, chosen, existing, read_at, raw) do
    case get_race_start(race_id) do
      nil ->
        {:error, :race_not_started}

      %RaceStart{} = race_start ->
        elapsed_ms = DateTime.diff(read_at, race_start.started_at, :millisecond)

        needs_review =
          length(splits) > 1 and
            flag_for_review?(chosen, existing, elapsed_ms, participant.id)

        case record_split_time(%{
               participant_id: participant.id,
               split_id: chosen.id,
               absolute_time: read_at,
               elapsed_ms: elapsed_ms,
               source: :chip,
               raw_chip_data: Jason.encode!(raw),
               needs_review: needs_review
             }) do
          {:ok, split_time} ->
            split_time = %{split_time | split: chosen}

            broadcast_station_read(race_id, station.id, %{
              status: :recorded,
              chip_id: Map.get(raw, "chip_id"),
              participant_id: participant.id,
              bib_number: participant.bib_number,
              split_id: chosen.id,
              split_name: chosen.name,
              elapsed_ms: elapsed_ms,
              needs_review: needs_review
            })

            {:ok, :recorded, participant, split_time}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  # The participant's recorded times for this race, with each split's
  # sort_order — one query feeding lockout, split selection and flagging.
  defp existing_split_entries(participant_id, race_id) do
    SplitTime
    |> join(:inner, [st], s in assoc(st, :split))
    |> where([st, s], st.participant_id == ^participant_id and s.race_id == ^race_id)
    |> select([st, s], %{
      split_id: st.split_id,
      sort_order: s.sort_order,
      absolute_time: st.absolute_time
    })
    |> Repo.all()
  end

  # The lowest-sort_order assigned split the participant has no time for.
  defp choose_split(splits, existing) do
    existing_ids = MapSet.new(existing, & &1.split_id)
    Enum.find(splits, fn split -> not MapSet.member?(existing_ids, split.id) end)
  end

  # A read close to the participant's previous recorded pass at this station
  # is a re-read (lingering in the antenna zone), not the next pass. Compares
  # against the device read_at so buffered/late uploads are judged by when
  # the pass actually happened. Times without an absolute_time (CSV imports)
  # can't participate.
  defp locked_out?(_existing, _splits, _read_at, 0), do: false

  defp locked_out?(existing, splits, read_at, lockout_seconds) do
    station_split_ids = MapSet.new(splits, & &1.id)

    Enum.any?(existing, fn entry ->
      MapSet.member?(station_split_ids, entry.split_id) and
        entry.absolute_time != nil and
        abs(DateTime.diff(read_at, entry.absolute_time, :second)) < lockout_seconds
    end)
  end

  # A multi-split attribution is suspicious when the elapsed time is
  # non-positive, the participant already has a later split recorded
  # (out-of-order backfill), or the elapsed time is far outside what the
  # rest of the field posted for the same split — typically a missed
  # earlier pass being credited to the wrong split.
  defp flag_for_review?(chosen, existing, elapsed_ms, participant_id) do
    elapsed_ms <= 0 or
      Enum.any?(existing, fn entry -> entry.sort_order > chosen.sort_order end) or
      outlier?(chosen.id, participant_id, elapsed_ms)
  end

  defp outlier?(split_id, participant_id, elapsed_ms) do
    others =
      SplitTime
      |> where([st], st.split_id == ^split_id and st.participant_id != ^participant_id)
      |> select([st], st.elapsed_ms)
      |> Repo.all()

    if length(others) >= @outlier_min_samples do
      m = median(others)
      elapsed_ms < div(m, @outlier_band) or elapsed_ms > m * @outlier_band
    else
      false
    end
  end

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    mid = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, mid)
    else
      div(Enum.at(sorted, mid - 1) + Enum.at(sorted, mid), 2)
    end
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
