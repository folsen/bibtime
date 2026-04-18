defmodule Bibtime.Photos.Storage do
  @moduledoc """
  File storage abstraction for race photos.

  ## Backends

    * `:local` (default) — files live under `priv/static/uploads/...` and
      `file_path` is the absolute URL path, e.g. `/uploads/races/1/photos/x.jpg`.
    * `:s3` — files live in an S3-compatible bucket (AWS S3 or Tigris) and
      `file_path` stores only the object key, e.g. `races/1/photos/x.jpg`.
      URLs are minted on demand via `presigned_url/1` by a controller that
      enforces per-race access control.
  """

  @doc """
  Stores an uploaded file and returns the stored reference:
  an absolute URL path for local, or the object key for S3.
  """
  def store(race_id, filename, source_path) do
    case backend() do
      :local -> store_local(race_id, filename, source_path)
      :s3 -> store_s3(race_id, filename, source_path)
    end
  end

  @doc """
  Deletes a stored file, accepting either a local `/uploads/...` path or an
  S3 object key.
  """
  def delete(file_path) do
    case backend() do
      :local -> delete_local(file_path)
      :s3 -> delete_s3(file_path)
    end
  end

  @doc """
  Whether the S3 backend is active.
  """
  def s3?, do: backend() == :s3

  @doc """
  Returns a short-lived signed URL for a stored S3 object key.
  """
  def presigned_url(key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 300)

    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, s3_config()[:bucket], key, expires_in: expires_in)
  end

  # --- Local storage ---

  defp store_local(race_id, filename, source_path) do
    dest_dir = Path.join(["priv/static/uploads/races", to_string(race_id), "photos"])
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, filename)
    File.cp!(source_path, dest_path)

    {:ok, "/uploads/races/#{race_id}/photos/#{filename}"}
  end

  defp delete_local(file_path) do
    full_path = Path.join("priv/static", String.trim_leading(file_path, "/"))

    case File.rm(full_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  # --- S3 storage ---

  defp store_s3(race_id, filename, source_path) do
    bucket = s3_config()[:bucket]
    key = "races/#{race_id}/photos/#{filename}"
    body = File.read!(source_path)
    content_type = MIME.from_path(filename)

    case ExAws.request(ExAws.S3.put_object(bucket, key, body, content_type: content_type)) do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_s3(file_path) do
    bucket = s3_config()[:bucket]
    key = String.trim_leading(file_path, "/")

    case ExAws.request(ExAws.S3.delete_object(bucket, key)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Config ---

  defp backend do
    case Application.get_env(:bibtime, __MODULE__) do
      nil -> :local
      config -> Keyword.get(config, :backend, :local)
    end
  end

  defp s3_config do
    Application.get_env(:bibtime, __MODULE__, [])
  end
end
