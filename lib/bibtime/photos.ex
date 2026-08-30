defmodule Bibtime.Photos do
  @moduledoc """
  The Photos context.

  Manages race photo uploads, bib tagging, moderation and retrieval.

  Photos carry a `status`. Organizer uploads are `:approved` immediately;
  participant submissions land as `:pending` and only join the general gallery
  once an admin approves them. Every read function defaults to approved-only so
  a forgotten option can't leak an unreviewed photo.
  """

  import Ecto.Query, warn: false
  alias Bibtime.AuditLog
  alias Bibtime.Accounts.User
  alias Bibtime.Participants
  alias Bibtime.Photos.PhotoNotifier
  alias Bibtime.Photos.RacePhoto
  alias Bibtime.Photos.Storage
  alias Bibtime.Races.Race
  alias Bibtime.RateLimiter
  alias Bibtime.Repo

  # Race statuses during which participants may submit photos.
  @uploadable_race_statuses [:in_progress, :finished]

  # Per-user submission throttle and outstanding-queue cap.
  @uploads_per_hour 50
  @max_pending_per_user 30

  ## Access control

  @doc """
  Whether the given user can view approved photos for the given race.

  * Public races (`race.photos_public: true`) are viewable by anyone.
  * Otherwise: admins, and participants of the race.
  """
  def can_view?(%{photos_public: true}, _user), do: true
  def can_view?(_race, nil), do: false

  def can_view?(race, %User{} = user) do
    User.admin?(user) or Participants.user_participant_in_race?(user.id, race.id)
  end

  @doc """
  Whether the given user may submit photos to the given race.

  Deliberately stricter than `can_view?/2`: a public-photo race is readable by
  anyone, but only a logged-in participant of that race (or an admin) may
  contribute to it, and only once the race is under way or done.
  """
  def can_upload?(race, user), do: authorize_upload(race, user) == :ok

  @doc """
  Whether the given user may see one specific photo.

  Approved photos follow `can_view?/2`. Pending and rejected photos are visible
  only to the uploader and to admins.
  """
  def can_view_photo?(%RacePhoto{status: :approved}, race, user), do: can_view?(race, user)
  def can_view_photo?(%RacePhoto{}, _race, nil), do: false

  def can_view_photo?(%RacePhoto{} = photo, _race, %User{} = user) do
    User.admin?(user) or photo.uploaded_by_user_id == user.id
  end

  defp authorize_upload(_race, nil), do: {:error, :unauthenticated}

  defp authorize_upload(race, %User{} = user) do
    cond do
      User.admin?(user) -> :ok
      not race.photo_uploads_enabled -> {:error, :uploads_disabled}
      race.status not in @uploadable_race_statuses -> {:error, :race_not_open_for_uploads}
      Participants.user_participant_in_race?(user.id, race.id) -> :ok
      true -> {:error, :not_a_participant}
    end
  end

  ## URLs

  @doc """
  Returns the URL to use in `<img src>` for a photo.

  Always the app's auth-gated `/photos/:id` route: it streams local files and
  302s to a signed URL on S3, checking `can_view_photo?/3` either way. Photos
  are never served straight off disk, so unapproved submissions stay private.
  """
  def display_url(%RacePhoto{id: id}), do: "/photos/#{id}"

  ## Listing

  @doc """
  Lists photos for a race.

  Options:

    * `:status` — `:approved` (default), `:pending`, `:rejected`, a list of
      statuses, or `:all`.
    * `:preload` — associations to preload, e.g. `:uploaded_by`.
  """
  def list_photos(race_id, opts \\ []) do
    RacePhoto
    |> where([p], p.race_id == ^race_id)
    |> with_status(Keyword.get(opts, :status, :approved))
    |> preload(^Keyword.get(opts, :preload, []))
    |> order_by([p], asc: p.sort_order, desc: p.inserted_at)
    |> Repo.all()
  end

  def list_photos_for_bib(race_id, bib_number, opts \\ []) do
    race_id
    |> list_photos(opts)
    |> Enum.filter(fn photo -> bib_number in (photo.bib_numbers || []) end)
  end

  def count_photos(race_id, opts \\ []) do
    RacePhoto
    |> where([p], p.race_id == ^race_id)
    |> with_status(Keyword.get(opts, :status, :approved))
    |> Repo.aggregate(:count)
  end

  def search_photos(race_id, query, opts \\ [])

  def search_photos(race_id, "", opts), do: list_photos(race_id, opts)

  def search_photos(race_id, query, opts) do
    term = String.downcase(query)

    race_id
    |> list_photos(opts)
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

  @doc """
  Submissions awaiting review, oldest first so the queue is fair.
  """
  def list_pending_photos(race_id) do
    RacePhoto
    |> where([p], p.race_id == ^race_id and p.status == :pending)
    |> order_by([p], asc: p.inserted_at)
    |> preload(:uploaded_by)
    |> Repo.all()
  end

  def count_pending_photos(race_id), do: count_photos(race_id, status: :pending)

  @doc """
  Pending counts for every race that has any, as a `%{race_id => count}` map.
  Drives the review badges in the admin nav.
  """
  def count_pending_photos_by_race do
    RacePhoto
    |> where([p], p.status == :pending)
    |> group_by([p], p.race_id)
    |> select([p], {p.race_id, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  A user's own submissions for a race, in any status, newest first.
  """
  def list_own_photos(_race_id, nil), do: []

  def list_own_photos(race_id, user_id) do
    RacePhoto
    |> where([p], p.race_id == ^race_id and p.uploaded_by_user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  defp with_status(query, :all), do: query

  defp with_status(query, statuses) when is_list(statuses),
    do: where(query, [p], p.status in ^statuses)

  defp with_status(query, status), do: where(query, [p], p.status == ^status)

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
    # Delete the row first: an orphaned file is harmless, an orphaned row
    # renders as a broken image for everyone.
    case Repo.delete(photo) do
      {:ok, deleted} ->
        Storage.delete(photo.file_path)
        {:ok, deleted}

      error ->
        error
    end
  end

  def change_photo(%RacePhoto{} = photo, attrs \\ %{}) do
    RacePhoto.changeset(photo, attrs)
  end

  ## Moderation

  @doc """
  Approves a pending submission, publishing it to the general gallery.
  """
  def approve_photo(%RacePhoto{} = photo, %User{} = admin) do
    case do_approve(photo, admin) do
      {:ok, updated, notify?} ->
        if notify?, do: notify_approved([updated], admin)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Rejects a submission. The optional reason is shown back to the uploader.
  """
  def reject_photo(%RacePhoto{} = photo, %User{} = admin, reason \\ nil) do
    reason = presence(reason)

    case review(photo, admin, %{
           status: :rejected,
           rejection_reason: reason,
           reviewed_by_user_id: admin.id,
           reviewed_at: now()
         }) do
      {:ok, updated} ->
        notify_rejected(updated, admin, reason)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Approves many photos at once. Returns the number approved.

  Uploaders hear once per bulk action, not once per photo.
  """
  def approve_photos(photo_ids, %User{} = admin) do
    approved =
      photo_ids
      |> Enum.map(&get_photo!/1)
      |> Enum.flat_map(fn photo ->
        case do_approve(photo, admin) do
          {:ok, updated, true} -> [updated]
          _ -> []
        end
      end)

    notify_approved(approved, admin)

    length(approved)
  end

  defp do_approve(%RacePhoto{} = photo, admin) do
    was_unpublished = photo.status != :approved

    case review(photo, admin, %{
           status: :approved,
           rejection_reason: nil,
           reviewed_by_user_id: admin.id,
           reviewed_at: now()
         }) do
      {:ok, updated} -> {:ok, updated, was_unpublished}
      error -> error
    end
  end

  ## Notifications

  @doc """
  Tells the organizers that a batch of submissions is waiting for review.

  Called once per submission batch rather than once per photo — a participant
  uploading ten shots should generate one email, not ten.
  """
  def notify_pending_submissions(race, count) when count > 0 do
    PhotoNotifier.deliver_pending_review_notice(race, count)
  end

  def notify_pending_submissions(_race, _count), do: :ok

  defp notify_approved([], _admin), do: :ok

  defp notify_approved(photos, admin) do
    photos
    |> Enum.reject(&(is_nil(&1.uploaded_by_user_id) or &1.uploaded_by_user_id == admin.id))
    |> Enum.group_by(& &1.uploaded_by_user_id)
    |> Enum.each(fn {user_id, group} ->
      with %User{} = user <- Repo.get(User, user_id),
           race when not is_nil(race) <- Repo.get(Race, hd(group).race_id) do
        PhotoNotifier.deliver_photos_approved(user, race, length(group))
      end
    end)
  end

  defp notify_rejected(%RacePhoto{uploaded_by_user_id: nil}, _admin, _reason), do: :ok

  defp notify_rejected(%RacePhoto{} = photo, admin, reason) do
    if photo.uploaded_by_user_id == admin.id do
      :ok
    else
      with %User{} = user <- Repo.get(User, photo.uploaded_by_user_id),
           race when not is_nil(race) <- Repo.get(Race, photo.race_id) do
        PhotoNotifier.deliver_photo_rejected(user, race, reason)
      end
    end
  end

  defp review(photo, admin, attrs) do
    if User.admin?(admin) do
      photo
      |> RacePhoto.review_changeset(attrs)
      |> Repo.update()
      |> log_review(admin)
    else
      {:error, :unauthorized}
    end
  end

  defp log_review({:ok, photo}, admin) do
    AuditLog.log(admin, "photo.#{photo.status}", "race_photo", photo.id, %{
      "race_id" => photo.race_id,
      "uploaded_by_user_id" => photo.uploaded_by_user_id
    })

    {:ok, photo}
  end

  defp log_review(error, _admin), do: error

  ## Upload

  @doc """
  Stores an organizer upload. The resulting photo is approved immediately.
  """
  def store_upload(race_id, entry, temp_path, attrs \\ %{}) do
    with {:ok, ext, content_type} <- sniff_image(temp_path),
         {:ok, key} <- Storage.store(race_id, unique_filename(ext), temp_path) do
      %{
        race_id: race_id,
        file_path: key,
        original_filename: entry.client_name,
        content_type: content_type,
        file_size: entry.client_size,
        bib_numbers: []
      }
      |> Map.merge(attrs)
      |> create_photo()
    end
  end

  @doc """
  Stores a participant submission as `:pending`.

  Re-checks upload rights, the per-user throttle and the outstanding-queue cap
  before anything touches storage, so this is safe to call straight from a
  LiveView event handler.
  """
  def submit_photo(race, user, entry, temp_path, attrs \\ %{}) do
    with :ok <- authorize_upload(race, user),
         :ok <- check_upload_rate(user),
         :ok <- check_pending_cap(race, user),
         {:ok, ext, content_type} <- sniff_image(temp_path),
         {:ok, key} <- Storage.store(race.id, unique_filename(ext), temp_path),
         {:ok, photo} <- insert_submission(race, user, entry, key, content_type, attrs) do
      AuditLog.log(user, "photo.submitted", "race_photo", photo.id, %{
        "race_id" => race.id
      })

      {:ok, photo}
    end
  end

  defp insert_submission(race, user, entry, key, content_type, attrs) do
    %RacePhoto{}
    |> RacePhoto.submission_changeset(%{
      race_id: race.id,
      file_path: key,
      original_filename: entry.client_name,
      content_type: content_type,
      file_size: entry.client_size,
      uploaded_by_user_id: user.id,
      caption: Map.get(attrs, :caption),
      bib_numbers: Map.get(attrs, :bib_numbers, [])
    })
    |> Repo.insert()
  end

  defp check_upload_rate(%User{} = user) do
    case RateLimiter.check_rate({:photo_upload, user.id}, @uploads_per_hour, 3600) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end

  defp check_pending_cap(race, %User{} = user) do
    pending =
      RacePhoto
      |> where(
        [p],
        p.race_id == ^race.id and p.uploaded_by_user_id == ^user.id and p.status == :pending
      )
      |> Repo.aggregate(:count)

    if pending >= @max_pending_per_user do
      {:error, :pending_limit_reached}
    else
      :ok
    end
  end

  defp unique_filename(ext) do
    random = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    "#{System.unique_integer([:positive])}_#{random}#{ext}"
  end

  @doc """
  Identifies an image by its leading bytes, returning `{:ok, extension,
  content_type}`.

  The filename and content type reported by the browser are attacker-supplied,
  so the stored extension is derived from the file itself. Anything that isn't
  a recognised image is refused before it reaches storage.
  """
  def sniff_image(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> {:ok, ".jpg", "image/jpeg"}
      {:ok, <<0x89, "PNG\r\n", 0x1A, 0x0A, _::binary>>} -> {:ok, ".png", "image/png"}
      {:ok, <<"GIF87a", _::binary>>} -> {:ok, ".gif", "image/gif"}
      {:ok, <<"GIF89a", _::binary>>} -> {:ok, ".gif", "image/gif"}
      {:ok, <<"RIFF", _::binary-size(4), "WEBP", _::binary>>} -> {:ok, ".webp", "image/webp"}
      {:ok, _} -> {:error, :unsupported_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp presence(nil), do: nil

  defp presence(string) when is_binary(string) do
    case String.trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
