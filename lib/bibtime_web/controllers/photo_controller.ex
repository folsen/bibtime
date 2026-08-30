defmodule BibtimeWeb.PhotoController do
  use BibtimeWeb, :controller

  alias Bibtime.Photos
  alias Bibtime.Photos.Storage
  alias Bibtime.Races

  @signed_url_ttl 300

  @doc """
  Serves a race photo after checking that this user may see it.

  This is the only way photos reach a browser — neither backend exposes a
  directly-servable path — so pending and rejected submissions stay visible to
  their uploader and admins alone.
  """
  def show(conn, %{"id" => id}) do
    photo = Photos.get_photo!(id)
    race = Races.get_race!(photo.race_id)
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    if Photos.can_view_photo?(photo, race, user) do
      conn
      |> put_resp_header("cache-control", cache_control(photo))
      |> serve(photo)
    else
      not_found(conn)
    end
  end

  defp serve(conn, photo) do
    if Storage.s3?() do
      case Storage.presigned_url(photo.file_path, expires_in: @signed_url_ttl) do
        {:ok, url} -> redirect(conn, external: url)
        {:error, _reason} -> conn |> put_status(:internal_server_error) |> text("Storage error")
      end
    else
      path = Storage.local_path(photo.file_path)

      if File.regular?(path) do
        conn
        # charset: nil — images are binary, a charset parameter is meaningless
        |> put_resp_content_type(photo.content_type || MIME.from_path(path), nil)
        |> send_file(200, path)
      else
        not_found(conn)
      end
    end
  end

  # Unapproved photos must never sit in a shared cache, and approved ones are
  # still per-user authorized.
  defp cache_control(%{status: :approved}), do: "private, max-age=#{@signed_url_ttl - 30}"
  defp cache_control(_photo), do: "private, no-store"

  defp not_found(conn) do
    conn |> put_status(:not_found) |> text("Not found")
  end
end
