defmodule Bibtime.PhotosFixtures do
  @moduledoc """
  Test helpers for race photos.
  """

  alias Bibtime.Photos
  alias Bibtime.Photos.RacePhoto
  alias Bibtime.Repo

  # Smallest bytes that still satisfy the magic-byte sniffer.
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0>>
  @png <<0x89, "PNG\r\n", 0x1A, 0x0A, 0, 0, 0, 13>>
  @gif <<"GIF89a", 1, 0, 1, 0, 0, 0>>
  @webp <<"RIFF", 26::little-32, "WEBPVP8 ">>
  @not_an_image <<"%PDF-1.4\n%just text">>

  def image_bytes(:jpeg), do: @jpeg
  def image_bytes(:png), do: @png
  def image_bytes(:gif), do: @gif
  def image_bytes(:webp), do: @webp
  def image_bytes(:invalid), do: @not_an_image

  @doc """
  Writes a temporary file with the given image type's magic bytes and returns
  its path. Removed when the test process exits.
  """
  def image_file(type \\ :jpeg) do
    dir = Path.join(System.tmp_dir!(), "bibtime-test-uploads")
    File.mkdir_p!(dir)
    path = Path.join(dir, "#{System.unique_integer([:positive])}.bin")
    File.write!(path, image_bytes(type))
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end

  @doc """
  A stand-in for a `Phoenix.LiveView.UploadEntry`, carrying only the fields the
  Photos context reads.
  """
  def upload_entry(attrs \\ %{}) do
    Enum.into(attrs, %{
      client_name: "race.jpg",
      client_type: "image/jpeg",
      client_size: 1024
    })
  end

  @doc """
  Inserts a photo row directly, bypassing storage. Defaults to approved.
  """
  def photo_fixture(race, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        race_id: race.id,
        file_path: "races/#{race.id}/photos/#{System.unique_integer([:positive])}.jpg",
        original_filename: "race.jpg",
        content_type: "image/jpeg",
        file_size: 1024,
        status: :approved
      })

    %RacePhoto{}
    |> RacePhoto.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Inserts a pending submission attributed to `user`.
  """
  def pending_photo_fixture(race, user, attrs \\ %{}) do
    photo_fixture(
      race,
      Enum.into(attrs, %{status: :pending, uploaded_by_user_id: user.id})
    )
  end

  @doc """
  Stores a real file through the configured backend and returns the photo.
  """
  def stored_photo_fixture(race, attrs \\ %{}) do
    {:ok, photo} =
      Photos.store_upload(race.id, upload_entry(), image_file(:jpeg), attrs)

    photo
  end
end
