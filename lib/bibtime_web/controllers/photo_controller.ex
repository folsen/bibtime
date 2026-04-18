defmodule BibtimeWeb.PhotoController do
  use BibtimeWeb, :controller

  alias Bibtime.Photos
  alias Bibtime.Photos.Storage
  alias Bibtime.Races

  @signed_url_ttl 300

  def show(conn, %{"id" => id}) do
    photo = Photos.get_photo!(id)
    race = Races.get_race!(photo.race_id)
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    cond do
      not Photos.can_view?(race, user) ->
        conn |> put_status(:not_found) |> text("Not found")

      String.starts_with?(photo.file_path, "/") ->
        redirect(conn, to: photo.file_path)

      true ->
        case Storage.presigned_url(photo.file_path, expires_in: @signed_url_ttl) do
          {:ok, url} ->
            conn
            |> put_resp_header("cache-control", "private, max-age=#{@signed_url_ttl - 30}")
            |> redirect(external: url)

          {:error, _reason} ->
            conn |> put_status(:internal_server_error) |> text("Storage error")
        end
    end
  end
end
