defmodule Bibtime.Photos.Storage do
  @moduledoc """
  File storage abstraction for race photos.

  Both backends store the same thing in `RacePhoto.file_path`: an object key
  of the form `races/<race_id>/photos/<filename>`.

  ## Backends

    * `:local` (default) — files live under `local_root/0`, which is
      deliberately **outside** `priv/static` so `Plug.Static` cannot serve
      them. Reads go through `BibtimeWeb.PhotoController`, which enforces
      per-photo access control.
    * `:s3` — files live in an S3-compatible bucket (AWS S3 or Tigris). URLs
      are minted on demand via `presigned_url/1` by the same controller.

  Photos awaiting moderation must never be reachable without an authorization
  check, which is why neither backend hands out a directly-servable path.
  """

  @default_local_root "priv/photo_uploads"

  @doc """
  Stores an uploaded file and returns `{:ok, key}`.
  """
  def store(race_id, filename, source_path) do
    key = "races/#{race_id}/photos/#{filename}"

    case backend() do
      :local -> store_local(key, source_path)
      :s3 -> store_s3(key, source_path)
    end
  end

  @doc """
  Deletes a stored file. Accepts a key or a legacy `/uploads/...` path.
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

  @doc """
  Absolute path on disk for a local storage key.

  Keys beginning with `/` are legacy `/uploads/...` values written before
  photos moved out of the static tree; they still resolve under `priv/static`
  so pre-migration rows keep rendering.
  """
  def local_path("/" <> _ = legacy_path) do
    Path.join("priv/static", String.trim_leading(legacy_path, "/"))
  end

  def local_path(key), do: Path.join(local_root(), key)

  @doc """
  Root directory for the `:local` backend.

  Configure with an absolute path on a persistent volume when running the
  local backend in production.
  """
  def local_root do
    Application.get_env(:bibtime, __MODULE__, [])
    |> Keyword.get(:local_root, @default_local_root)
  end

  # --- Local storage ---

  defp store_local(key, source_path) do
    dest_path = local_path(key)
    File.mkdir_p!(Path.dirname(dest_path))
    File.cp!(source_path, dest_path)

    {:ok, key}
  end

  defp delete_local(file_path) do
    case File.rm(local_path(file_path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  # --- S3 storage ---

  defp store_s3(key, source_path) do
    bucket = s3_config()[:bucket]
    body = File.read!(source_path)
    content_type = MIME.from_path(key)

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
    Application.get_env(:bibtime, __MODULE__, [])
    |> Keyword.get(:backend, :local)
  end

  defp s3_config do
    Application.get_env(:bibtime, __MODULE__, [])
  end
end
