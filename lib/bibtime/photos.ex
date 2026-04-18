defmodule Bibtime.Photos do
  @moduledoc """
  The Photos context.
  Manages race photo uploads, bib tagging, and retrieval.
  """

  import Ecto.Query, warn: false
  alias Bibtime.Repo
  alias Bibtime.Accounts.User
  alias Bibtime.Participants
  alias Bibtime.Photos.RacePhoto
  alias Bibtime.Photos.Storage

  ## Access control

  @doc """
  Whether the given user can view photos for the given race.

  * Public races (`race.photos_public: true`) are viewable by anyone.
  * Otherwise: admins, and participants of the race.
  """
  def can_view?(%{photos_public: true}, _user), do: true
  def can_view?(_race, nil), do: false

  def can_view?(race, %User{} = user) do
    User.admin?(user) or Participants.user_participant_in_race?(user.id, race.id)
  end

  ## URLs

  @doc """
  Returns the URL to use in `<img src>` for a photo. For local storage this
  is the static path under `/uploads/...`; for S3/Tigris it's the app's
  auth-gated `/photos/:id` proxy route, which 302s to a signed URL.
  """
  def display_url(%RacePhoto{file_path: "/" <> _ = path}), do: path
  def display_url(%RacePhoto{id: id}), do: "/photos/#{id}"

  ## Listing

  def list_photos(race_id) do
    RacePhoto
    |> where([p], p.race_id == ^race_id)
    |> order_by([p], asc: p.sort_order, desc: p.inserted_at)
    |> Repo.all()
  end

  def list_photos_for_bib(race_id, bib_number) do
    list_photos(race_id)
    |> Enum.filter(fn photo ->
      bib_number in (photo.bib_numbers || [])
    end)
  end

  def count_photos(race_id) do
    RacePhoto
    |> where([p], p.race_id == ^race_id)
    |> Repo.aggregate(:count)
  end

  def search_photos(race_id, ""), do: list_photos(race_id)

  def search_photos(race_id, query) do
    term = String.downcase(query)

    list_photos(race_id)
    |> Enum.filter(fn photo ->
      bib_match =
        Enum.any?(photo.bib_numbers || [], fn bib ->
          String.contains?(String.downcase(bib), term)
        end)

      caption_match =
        photo.caption && String.contains?(String.downcase(photo.caption), term)

      bib_match || caption_match
    end)
  end

  ## CRUD

  def get_photo!(id), do: Repo.get!(RacePhoto, id)

  def create_photo(attrs) do
    %RacePhoto{}
    |> RacePhoto.changeset(attrs)
    |> Repo.insert()
  end

  def update_photo(%RacePhoto{} = photo, attrs) do
    photo
    |> RacePhoto.changeset(attrs)
    |> Repo.update()
  end

  def tag_photo(%RacePhoto{} = photo, attrs) do
    photo
    |> RacePhoto.tag_changeset(attrs)
    |> Repo.update()
  end

  def delete_photo(%RacePhoto{} = photo) do
    Storage.delete(photo.file_path)
    Repo.delete(photo)
  end

  def change_photo(%RacePhoto{} = photo, attrs \\ %{}) do
    RacePhoto.changeset(photo, attrs)
  end

  ## Upload

  def store_upload(race_id, entry, temp_path) do
    ext = Path.extname(entry.client_name) |> String.downcase()

    unique_name =
      "#{System.unique_integer([:positive])}_#{Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)}#{ext}"

    case Storage.store(race_id, unique_name, temp_path) do
      {:ok, url} ->
        create_photo(%{
          race_id: race_id,
          file_path: url,
          original_filename: entry.client_name,
          content_type: entry.client_type,
          file_size: entry.client_size,
          bib_numbers: []
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
