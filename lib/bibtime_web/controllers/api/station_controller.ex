defmodule BibtimeWeb.API.StationController do
  use BibtimeWeb, :controller

  alias Bibtime.Timing

  plug BibtimeWeb.API.StationAuth

  @doc """
  Accepts a single chip read and ingests it into the timing system.

  Expected body:
      {"chip_id": "E200...", "read_at": "2026-06-15T09:23:45.123Z", "rssi": -45}
  """
  def create_read(conn, params) do
    station = conn.assigns.station

    case normalize_read(params) do
      {:ok, read} ->
        result = Timing.ingest_chip_read(station, read)
        json(conn, read_result_to_json(result, read))

      {:error, :invalid_payload} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", reason: "invalid_payload"})
    end
  end

  @doc """
  Accepts a batch of chip reads (`{"reads": [...]}`) and returns a list of
  per-read results.
  """
  def create_reads_batch(conn, %{"reads" => reads}) when is_list(reads) do
    station = conn.assigns.station

    results =
      Enum.map(reads, fn raw ->
        case normalize_read(raw) do
          {:ok, read} ->
            result = Timing.ingest_chip_read(station, read)
            read_result_to_json(result, read)

          {:error, :invalid_payload} ->
            %{status: "error", reason: "invalid_payload"}
        end
      end)

    json(conn, %{results: results})
  end

  def create_reads_batch(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{status: "error", reason: "invalid_payload"})
  end

  @doc """
  Handles a periodic heartbeat from a station. The payload is stored in the
  station's metadata, `last_seen_at` is updated, and `status` is set to
  `:online`.
  """
  def heartbeat(conn, params) do
    station = conn.assigns.station

    metadata =
      params
      |> Map.drop(["token"])
      |> Map.take([
        "firmware_version",
        "reads_total",
        "buffer_size",
        "uptime_seconds",
        "reader_connected",
        "status",
        "error_reason"
      ])

    case Timing.update_station_heartbeat(station, metadata) do
      {:ok, _updated} ->
        json(conn, %{status: "ok"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "error", reason: "update_failed"})
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # The ingest function expects a map with string keys. Ensure there is a
  # "chip_id" entry, which is the only required field. Unknown/extra fields
  # are retained so they survive into `raw_chip_data`.
  defp normalize_read(%{"chip_id" => chip_id} = raw) when is_binary(chip_id) do
    {:ok, raw}
  end

  defp normalize_read(_), do: {:error, :invalid_payload}

  defp read_result_to_json({:ok, :recorded, participant, split_time}, _raw) do
    %{
      status: "recorded",
      participant_bib: participant.bib_number,
      participant_name: full_name(participant),
      elapsed_ms: split_time.elapsed_ms
    }
  end

  defp read_result_to_json({:ok, :duplicate, participant}, _raw) do
    %{
      status: "duplicate",
      participant_bib: participant.bib_number
    }
  end

  defp read_result_to_json({:ok, :unmatched}, raw) do
    %{status: "unmatched", chip_id: Map.get(raw, "chip_id")}
  end

  defp read_result_to_json({:error, :station_unassigned}, _raw) do
    %{status: "error", reason: "station_unassigned"}
  end

  defp read_result_to_json({:error, reason}, _raw) when is_atom(reason) do
    %{status: "error", reason: Atom.to_string(reason)}
  end

  defp read_result_to_json({:error, _other}, _raw) do
    %{status: "error", reason: "unknown"}
  end

  defp full_name(participant) do
    [participant.first_name, participant.last_name]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end
end
