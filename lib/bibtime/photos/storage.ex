defmodule Bibtime.Photos.Storage do
  @moduledoc """
  File storage abstraction for race photos.
  Defaults to local disk storage. Configure S3-compatible storage via environment variables.
  """

  @doc """
  Stores an uploaded file and returns the public URL path.
  """
  def store(race_id, filename, source_path) do
    case backend() do
      :local -> store_local(race_id, filename, source_path)
      :s3 -> store_s3(race_id, filename, source_path)
    end
  end

  @doc """
  Deletes a stored file by its path.
  """
  def delete(file_path) do
    case backend() do
      :local -> delete_local(file_path)
      :s3 -> delete_s3(file_path)
    end
  end

  @doc """
  Returns the public URL for a stored file.
  """
  def url(file_path), do: file_path

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
      {:ok, _} ->
        {:ok, s3_url(bucket, key)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_s3(file_path) do
    bucket = s3_config()[:bucket]
    # Extract key from URL or path
    key = String.trim_leading(file_path, "/")

    case ExAws.request(ExAws.S3.delete_object(bucket, key)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp s3_url(bucket, key) do
    region = Application.get_env(:ex_aws, :region, "us-east-1")

    case Application.get_env(:ex_aws, :s3) do
      nil ->
        "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"

      s3_config ->
        host = Keyword.get(s3_config, :host, "#{bucket}.s3.#{region}.amazonaws.com")
        scheme = Keyword.get(s3_config, :scheme, "https://")
        "#{scheme}#{host}/#{bucket}/#{key}"
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
