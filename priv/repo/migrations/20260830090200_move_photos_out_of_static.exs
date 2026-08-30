defmodule Bibtime.Repo.Migrations.MovePhotosOutOfStatic do
  use Ecto.Migration

  @moduledoc """
  Photos on the `:local` backend used to live in `priv/static/uploads` and were
  served by `Plug.Static` with no authorization. Moderation requires that
  unapproved photos are not reachable by URL, so files move to a non-static
  root and `file_path` becomes a plain object key, matching the S3 backend.

  S3 rows already store bare keys and are left untouched.
  """

  @default_local_root "priv/photo_uploads"
  @legacy_root "priv/static/uploads"

  def up do
    repo().query!("SELECT id, file_path FROM race_photos WHERE file_path LIKE '/uploads/%'", [])
    |> Map.get(:rows)
    |> Enum.each(fn [id, file_path] ->
      key = String.replace_prefix(file_path, "/uploads/", "")
      move_file(Path.join(@legacy_root, key), Path.join(local_root(), key))

      repo().query!("UPDATE race_photos SET file_path = ? WHERE id = ?", [key, id])
    end)
  end

  def down do
    repo().query!("SELECT id, file_path FROM race_photos WHERE file_path NOT LIKE '/%'", [])
    |> Map.get(:rows)
    |> Enum.each(fn [id, key] ->
      move_file(Path.join(local_root(), key), Path.join(@legacy_root, key))

      repo().query!("UPDATE race_photos SET file_path = ? WHERE id = ?", ["/uploads/" <> key, id])
    end)
  end

  # Copy-then-delete rather than rename: the destination may be on a different
  # filesystem, and a missing source must not abort the path rewrite.
  defp move_file(source, dest) do
    if File.regular?(source) do
      File.mkdir_p!(Path.dirname(dest))

      case File.cp(source, dest) do
        :ok -> File.rm(source)
        {:error, _} -> :ok
      end
    end

    :ok
  end

  defp local_root do
    Application.get_env(:bibtime, Bibtime.Photos.Storage, [])
    |> Keyword.get(:local_root, @default_local_root)
  end
end
