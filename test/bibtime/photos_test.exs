defmodule Bibtime.PhotosTest do
  use Bibtime.DataCase

  alias Bibtime.Photos
  alias Bibtime.Photos.RacePhoto
  alias Bibtime.Photos.Storage

  import Bibtime.AccountsFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PhotosFixtures
  import Bibtime.RacesFixtures

  # Rate-limit buckets are keyed by user id, and the sandbox hands out the same
  # ids to every test, so clear them between tests.
  setup do
    Bibtime.RateLimiter.reset()
    :ok
  end

  defp finished_race(attrs \\ %{}) do
    race_fixture(Map.merge(%{status: :finished}, attrs))
  end

  defp submit_many(race, user, count) do
    for _ <- 1..count do
      {:ok, _} = Photos.submit_photo(race, user, upload_entry(), image_file(), %{})
    end
  end

  defp participant_user(race) do
    user = user_fixture()
    participant_fixture(race, %{email: user.email})
    user
  end

  describe "can_upload?/2" do
    setup do
      %{race: finished_race()}
    end

    test "rejects anonymous visitors", %{race: race} do
      refute Photos.can_upload?(race, nil)
    end

    test "rejects a logged-in user who is not in the race", %{race: race} do
      refute Photos.can_upload?(race, user_fixture())
    end

    test "allows a participant of the race", %{race: race} do
      assert Photos.can_upload?(race, participant_user(race))
    end

    test "allows admins regardless of participation", %{race: race} do
      assert Photos.can_upload?(race, admin_user_fixture())
    end

    test "allows uploads while the race is in progress" do
      race = race_fixture(%{status: :in_progress})
      assert Photos.can_upload?(race, participant_user(race))
    end

    test "refuses before the race starts and after it is archived" do
      for status <- [:draft, :registration_open, :registration_closed, :archived] do
        race = race_fixture(%{status: status})
        refute Photos.can_upload?(race, participant_user(race))
      end
    end

    test "refuses when the organizer turned submissions off" do
      race = finished_race(%{photo_uploads_enabled: false})
      refute Photos.can_upload?(race, participant_user(race))
    end

    test "a public-photo race is still not open to non-participants" do
      race = finished_race(%{photos_public: true})
      user = user_fixture()

      assert Photos.can_view?(race, user)
      refute Photos.can_upload?(race, user)
    end
  end

  describe "listing defaults to approved photos only" do
    setup do
      race = finished_race()
      user = participant_user(race)

      approved = photo_fixture(race, %{caption: "finish line"})
      pending = pending_photo_fixture(race, user, %{caption: "finish line"})
      rejected = photo_fixture(race, %{status: :rejected, caption: "finish line"})

      %{race: race, user: user, approved: approved, pending: pending, rejected: rejected}
    end

    test "list_photos/1 hides pending and rejected", %{race: race, approved: approved} do
      assert [%RacePhoto{id: id}] = Photos.list_photos(race.id)
      assert id == approved.id
    end

    test "list_photos/2 can widen the status", %{race: race} do
      assert length(Photos.list_photos(race.id, status: :all)) == 3
      assert length(Photos.list_photos(race.id, status: :pending)) == 1
      assert length(Photos.list_photos(race.id, status: [:pending, :rejected])) == 2
    end

    test "count_photos/1 counts approved only", %{race: race} do
      assert Photos.count_photos(race.id) == 1
      assert Photos.count_photos(race.id, status: :all) == 3
    end

    test "search_photos/2 never surfaces unapproved photos", %{race: race} do
      assert length(Photos.search_photos(race.id, "finish")) == 1
      assert length(Photos.search_photos(race.id, "")) == 1
    end

    test "list_photos_for_bib/2 skips unapproved photos", %{race: race, user: user} do
      photo_fixture(race, %{bib_numbers: ["7"]})
      pending_photo_fixture(race, user, %{bib_numbers: ["7"]})

      assert length(Photos.list_photos_for_bib(race.id, "7")) == 1
    end

    test "list_pending_photos/1 returns the queue with uploaders", %{race: race, user: user} do
      assert [photo] = Photos.list_pending_photos(race.id)
      assert photo.uploaded_by.id == user.id
    end

    test "count_pending_photos_by_race/0 groups by race", %{race: race} do
      assert Photos.count_pending_photos_by_race() == %{race.id => 1}
    end

    test "list_own_photos/2 returns the uploader's rows in any status", %{
      race: race,
      user: user,
      pending: pending
    } do
      assert [%RacePhoto{id: id}] = Photos.list_own_photos(race.id, user.id)
      assert id == pending.id
      assert Photos.list_own_photos(race.id, nil) == []
    end
  end

  describe "can_view_photo?/3" do
    setup do
      race = finished_race(%{photos_public: true})
      uploader = participant_user(race)

      %{
        race: race,
        uploader: uploader,
        pending: pending_photo_fixture(race, uploader),
        approved: photo_fixture(race)
      }
    end

    test "approved photos follow race visibility", %{race: race, approved: approved} do
      assert Photos.can_view_photo?(approved, race, nil)
      assert Photos.can_view_photo?(approved, race, user_fixture())
    end

    test "pending photos are hidden from anonymous visitors", %{race: race, pending: pending} do
      refute Photos.can_view_photo?(pending, race, nil)
    end

    test "pending photos are hidden from other users", %{race: race, pending: pending} do
      refute Photos.can_view_photo?(pending, race, user_fixture())
      refute Photos.can_view_photo?(pending, race, participant_user(race))
    end

    test "the uploader and admins can see a pending photo", %{
      race: race,
      pending: pending,
      uploader: uploader
    } do
      assert Photos.can_view_photo?(pending, race, uploader)
      assert Photos.can_view_photo?(pending, race, admin_user_fixture())
    end

    test "rejected photos stay visible only to the uploader", %{race: race, uploader: uploader} do
      rejected = photo_fixture(race, %{status: :rejected, uploaded_by_user_id: uploader.id})

      assert Photos.can_view_photo?(rejected, race, uploader)
      refute Photos.can_view_photo?(rejected, race, user_fixture())
    end
  end

  describe "moderation" do
    setup do
      race = finished_race()
      uploader = participant_user(race)

      %{
        race: race,
        admin: admin_user_fixture(),
        uploader: uploader,
        photo: pending_photo_fixture(race, uploader)
      }
    end

    test "approve_photo/2 publishes and records the reviewer", %{photo: photo, admin: admin} do
      assert {:ok, approved} = Photos.approve_photo(photo, admin)
      assert approved.status == :approved
      assert approved.reviewed_by_user_id == admin.id
      assert approved.reviewed_at
    end

    test "approve_photo/2 makes the photo public", %{race: race, photo: photo, admin: admin} do
      assert Photos.list_photos(race.id) == []
      {:ok, _} = Photos.approve_photo(photo, admin)
      assert [%RacePhoto{}] = Photos.list_photos(race.id)
    end

    test "reject_photo/3 stores a trimmed reason", %{photo: photo, admin: admin} do
      assert {:ok, rejected} = Photos.reject_photo(photo, admin, "  blurry  ")
      assert rejected.status == :rejected
      assert rejected.rejection_reason == "blurry"
    end

    test "reject_photo/3 treats a blank reason as none", %{photo: photo, admin: admin} do
      assert {:ok, rejected} = Photos.reject_photo(photo, admin, "   ")
      assert rejected.rejection_reason == nil
    end

    test "a rejected photo can be published afterwards", %{photo: photo, admin: admin} do
      {:ok, rejected} = Photos.reject_photo(photo, admin, "wrong race")
      assert {:ok, approved} = Photos.approve_photo(rejected, admin)
      assert approved.status == :approved
      assert approved.rejection_reason == nil
    end

    test "non-admins cannot review", %{photo: photo, uploader: uploader} do
      assert {:error, :unauthorized} = Photos.approve_photo(photo, uploader)
      assert {:error, :unauthorized} = Photos.reject_photo(photo, uploader, "mine")
      assert Photos.get_photo!(photo.id).status == :pending
    end

    test "approve_photos/2 returns how many it published", %{
      race: race,
      uploader: uploader,
      admin: admin
    } do
      second = pending_photo_fixture(race, uploader)
      first = pending_photo_fixture(race, uploader)

      assert Photos.approve_photos([first.id, second.id], admin) == 2
      assert Photos.count_pending_photos(race.id) == 1
    end

    test "reviewing writes an audit entry", %{photo: photo, admin: admin} do
      {:ok, _} = Photos.approve_photo(photo, admin)

      assert Enum.any?(Bibtime.AuditLog.list_entries(), &(&1.action == "photo.approved"))
    end
  end

  describe "submit_photo/5" do
    setup do
      race = finished_race()
      %{race: race, user: participant_user(race)}
    end

    test "stores a pending photo attributed to the uploader", %{race: race, user: user} do
      assert {:ok, photo} =
               Photos.submit_photo(race, user, upload_entry(), image_file(:jpeg), %{
                 caption: "my race",
                 bib_numbers: ["12"]
               })

      assert photo.status == :pending
      assert photo.uploaded_by_user_id == user.id
      assert photo.caption == "my race"
      assert photo.bib_numbers == ["12"]
      assert File.regular?(Storage.local_path(photo.file_path))
    end

    test "refuses a user who may not upload", %{race: race} do
      assert {:error, :not_a_participant} =
               Photos.submit_photo(race, user_fixture(), upload_entry(), image_file(), %{})
    end

    test "refuses when the race is closed to submissions", %{user: user} do
      race = finished_race(%{photo_uploads_enabled: false})

      assert {:error, :uploads_disabled} =
               Photos.submit_photo(race, user, upload_entry(), image_file(), %{})
    end

    test "refuses a file that is not an image", %{race: race, user: user} do
      assert {:error, :unsupported_type} =
               Photos.submit_photo(race, user, upload_entry(), image_file(:invalid), %{})

      assert Photos.count_pending_photos(race.id) == 0
    end

    test "the stored extension comes from the bytes, not the filename", %{
      race: race,
      user: user
    } do
      entry = upload_entry(%{client_name: "sneaky.php", client_type: "application/x-php"})

      assert {:ok, photo} = Photos.submit_photo(race, user, entry, image_file(:png), %{})
      assert Path.extname(photo.file_path) == ".png"
      assert photo.content_type == "image/png"
      assert photo.original_filename == "sneaky.php"
    end

    test "an uploader cannot self-approve through the changeset", %{race: race, user: user} do
      changeset =
        RacePhoto.submission_changeset(%RacePhoto{}, %{
          race_id: race.id,
          file_path: "races/1/photos/x.jpg",
          uploaded_by_user_id: user.id,
          status: :approved,
          caption: "hi"
        })

      assert Ecto.Changeset.get_field(changeset, :status) == :pending
    end

    test "caps how many submissions one person can leave unreviewed", %{race: race, user: user} do
      submit_many(race, user, 30)

      assert {:error, :pending_limit_reached} =
               Photos.submit_photo(race, user, upload_entry(), image_file(), %{})
    end

    test "reviewing clears the outstanding cap", %{race: race, user: user} do
      submit_many(race, user, 30)

      Photos.approve_photos(
        Enum.map(Photos.list_pending_photos(race.id), & &1.id),
        admin_user_fixture()
      )

      assert {:ok, _} = Photos.submit_photo(race, user, upload_entry(), image_file(), %{})
    end

    test "stops accepting uploads past the hourly limit", %{race: race, user: user} do
      admin = admin_user_fixture()

      # The outstanding-review cap (30) bites first, so clear the queue before
      # continuing towards the hourly ceiling of 50.
      submit_many(race, user, 30)
      Photos.approve_photos(Enum.map(Photos.list_pending_photos(race.id), & &1.id), admin)
      submit_many(race, user, 20)

      assert {:error, :rate_limited} =
               Photos.submit_photo(race, user, upload_entry(), image_file(), %{})
    end
  end

  describe "sniff_image/1" do
    test "recognises the supported formats" do
      assert {:ok, ".jpg", "image/jpeg"} = Photos.sniff_image(image_file(:jpeg))
      assert {:ok, ".png", "image/png"} = Photos.sniff_image(image_file(:png))
      assert {:ok, ".gif", "image/gif"} = Photos.sniff_image(image_file(:gif))
      assert {:ok, ".webp", "image/webp"} = Photos.sniff_image(image_file(:webp))
    end

    test "refuses anything else" do
      assert {:error, :unsupported_type} = Photos.sniff_image(image_file(:invalid))
    end
  end

  describe "display_url/1" do
    test "always routes through the authorized controller" do
      race = finished_race()
      photo = photo_fixture(race)

      assert Photos.display_url(photo) == "/photos/#{photo.id}"
    end
  end

  describe "delete_photo/1" do
    test "removes the row and the stored file" do
      race = finished_race()
      photo = stored_photo_fixture(race)
      path = Storage.local_path(photo.file_path)

      assert File.regular?(path)
      assert {:ok, _} = Photos.delete_photo(photo)
      refute File.regular?(path)
      assert Photos.list_photos(race.id, status: :all) == []
    end
  end
end
