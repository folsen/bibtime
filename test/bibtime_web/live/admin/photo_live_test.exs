defmodule BibtimeWeb.Admin.PhotoLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PhotosFixtures
  import Bibtime.RacesFixtures

  alias Bibtime.Photos

  setup :register_and_log_in_admin_user

  setup do
    race = race_fixture(%{status: :finished})
    uploader = user_fixture()
    participant_fixture(race, %{email: uploader.email})

    %{race: race, uploader: uploader}
  end

  describe "the review queue" do
    test "opens on pending when submissions are waiting", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      pending_photo_fixture(race, uploader, %{original_filename: "waiting.jpg"})
      photo_fixture(race, %{original_filename: "published.jpg"})

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      assert html =~ "waiting.jpg"
      refute html =~ "published.jpg"
      assert html =~ "1 awaiting review"
      assert html =~ "Pending (1)"
    end

    test "opens on published when the queue is empty", %{conn: conn, race: race} do
      photo_fixture(race, %{original_filename: "published.jpg"})

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      assert html =~ "published.jpg"
      refute html =~ "awaiting review"
    end

    test "names the submitter", %{conn: conn, race: race, uploader: uploader} do
      pending_photo_fixture(race, uploader)

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      assert html =~ uploader.email
    end

    test "filters by status", %{conn: conn, race: race, uploader: uploader} do
      pending_photo_fixture(race, uploader, %{original_filename: "waiting.jpg"})
      photo_fixture(race, %{original_filename: "published.jpg"})
      photo_fixture(race, %{status: :rejected, original_filename: "turned-down.jpg"})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      html = view |> element("a", "Rejected") |> render_click()
      assert html =~ "turned-down.jpg"
      refute html =~ "waiting.jpg"

      html = view |> element("a", "All") |> render_click()
      assert html =~ "turned-down.jpg"
      assert html =~ "waiting.jpg"
      assert html =~ "published.jpg"
    end
  end

  describe "approving" do
    test "publishes a submission to the gallery", %{conn: conn, race: race, uploader: uploader} do
      photo = pending_photo_fixture(race, uploader)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      render_click(view, "approve_photo", %{"id" => to_string(photo.id)})

      assert Photos.get_photo!(photo.id).status == :approved
      assert [_] = Photos.list_photos(race.id)
    end

    test "approves a selected subset", %{conn: conn, race: race, uploader: uploader} do
      keep = pending_photo_fixture(race, uploader)
      other = pending_photo_fixture(race, uploader)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      render_click(view, "toggle_selected", %{"id" => to_string(keep.id)})
      render_click(view, "approve_selected", %{})

      assert Photos.get_photo!(keep.id).status == :approved
      assert Photos.get_photo!(other.id).status == :pending
    end

    test "approves the whole queue at once", %{conn: conn, race: race, uploader: uploader} do
      for _ <- 1..3, do: pending_photo_fixture(race, uploader)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      render_click(view, "approve_all_pending", %{})

      assert Photos.count_pending_photos(race.id) == 0
      assert length(Photos.list_photos(race.id)) == 3
    end
  end

  describe "rejecting" do
    test "records the reason and keeps the photo out of the gallery", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      photo = pending_photo_fixture(race, uploader)

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      render_click(view, "start_reject", %{"id" => to_string(photo.id)})

      render_submit(view, "reject_photo", %{"id" => to_string(photo.id), "reason" => "Wrong race"})

      photo = Photos.get_photo!(photo.id)
      assert photo.status == :rejected
      assert photo.rejection_reason == "Wrong race"
      assert Photos.list_photos(race.id) == []
    end

    test "a rejected photo can still be published later", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      photo = photo_fixture(race, %{status: :rejected, uploaded_by_user_id: uploader.id})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos?status=rejected")

      render_click(view, "approve_photo", %{"id" => to_string(photo.id)})

      assert Photos.get_photo!(photo.id).status == :approved
    end
  end

  describe "organizer uploads" do
    test "publish immediately without review", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      entry =
        file_input(view, "#upload-form", :photos, [
          %{
            name: "official.jpg",
            content: image_bytes(:jpeg),
            type: "image/jpeg",
            size: byte_size(image_bytes(:jpeg))
          }
        ])

      render_upload(entry, "official.jpg")
      render_submit(view, "save_uploads", %{})

      assert [photo] = Photos.list_photos(race.id)
      assert photo.status == :approved
      assert Photos.count_pending_photos(race.id) == 0
    end

    test "a file that isn't an image is skipped", %{conn: conn, race: race} do
      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      entry =
        file_input(view, "#upload-form", :photos, [
          %{
            name: "notes.jpg",
            content: image_bytes(:invalid),
            type: "image/jpeg",
            size: byte_size(image_bytes(:invalid))
          }
        ])

      render_upload(entry, "notes.jpg")
      render_submit(view, "save_uploads", %{})

      assert Photos.list_photos(race.id, status: :all) == []
    end
  end

  describe "tagging" do
    test "an admin can fix bib numbers before approving", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      photo = pending_photo_fixture(race, uploader, %{bib_numbers: ["999"]})

      {:ok, view, _html} = live(conn, ~p"/admin/races/#{race.id}/photos")

      render_click(view, "edit_photo", %{"id" => to_string(photo.id)})

      render_submit(view, "save_tags", %{
        "id" => to_string(photo.id),
        "bib_numbers" => "12, 13",
        "caption" => "Final straight",
        "split_id" => ""
      })

      photo = Photos.get_photo!(photo.id)
      assert photo.bib_numbers == ["12", "13"]
      assert photo.caption == "Final straight"
      assert photo.status == :pending
    end
  end

  describe "access" do
    test "the race dashboard flags photos awaiting review", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      pending_photo_fixture(race, uploader)

      {:ok, _view, html} = live(conn, ~p"/admin/races/#{race.id}")

      assert html =~ "1 to review"
    end

    test "the races list links straight to the queue", %{
      conn: conn,
      race: race,
      uploader: uploader
    } do
      pending_photo_fixture(race, uploader)

      {:ok, _view, html} = live(conn, ~p"/admin/races")

      assert html =~ "1 to review"
      assert html =~ "/admin/races/#{race.id}/photos?status=pending"
    end
  end
end
