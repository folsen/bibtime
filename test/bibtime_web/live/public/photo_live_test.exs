defmodule BibtimeWeb.Public.PhotoLiveTest do
  use BibtimeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bibtime.AccountsFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PhotosFixtures
  import Bibtime.RacesFixtures

  alias Bibtime.Photos

  defp setup_race(attrs \\ %{}) do
    race = race_fixture(Map.merge(%{status: :finished, photos_public: true}, attrs))
    uploader = user_fixture()
    participant_fixture(race, %{email: uploader.email, bib_number: "42"})

    {race, uploader}
  end

  describe "the upload panel" do
    test "is offered to a participant after the race", %{conn: conn} do
      {race, uploader} = setup_race()

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      assert html =~ "Add your photos"
    end

    test "is hidden from a logged-out visitor, who is invited to log in", %{conn: conn} do
      {race, _uploader} = setup_race()

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}/photos")

      refute html =~ "Add your photos"
      assert html =~ "Took photos at this race?"
    end

    test "is hidden from a logged-in non-participant", %{conn: conn} do
      {race, _uploader} = setup_race()

      {:ok, _view, html} =
        conn |> log_in_user(user_fixture()) |> live(~p"/races/#{race.slug}/photos")

      refute html =~ "Add your photos"
    end

    test "is hidden before the race is under way", %{conn: conn} do
      {race, uploader} = setup_race(%{status: :registration_open})

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      refute html =~ "Add your photos"
    end

    test "is hidden when the organizer disabled submissions", %{conn: conn} do
      {race, uploader} = setup_race(%{photo_uploads_enabled: false})

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      refute html =~ "Add your photos"
    end

    test "prefills the participant's own bib number once files are chosen", %{conn: conn} do
      {race, uploader} = setup_race()

      {:ok, view, _html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      render_click(view, "open_upload", %{})

      entry =
        file_input(view, "#submission-form", :submissions, [
          %{
            name: "finish.jpg",
            content: image_bytes(:jpeg),
            type: "image/jpeg",
            size: byte_size(image_bytes(:jpeg))
          }
        ])

      assert render_upload(entry, "finish.jpg") =~ ~s(value="42")
    end
  end

  describe "submitting photos" do
    test "stores them as pending and tells the uploader they need review", %{conn: conn} do
      {race, uploader} = setup_race()

      {:ok, view, _html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      render_click(view, "open_upload", %{})

      entry =
        file_input(view, "#submission-form", :submissions, [
          %{
            name: "finish.jpg",
            content: image_bytes(:jpeg),
            type: "image/jpeg",
            size: byte_size(image_bytes(:jpeg))
          }
        ])

      assert render_upload(entry, "finish.jpg") =~ "Submit 1 photo"

      html =
        view
        |> form("#submission-form", %{"caption" => "my finish", "bib_numbers" => "42"})
        |> render_submit()

      assert html =~ "an organizer will review"
      assert html =~ "Your submissions"
      assert html =~ "Pending review"

      assert [photo] = Photos.list_pending_photos(race.id)
      assert photo.uploaded_by_user_id == uploader.id
      assert photo.caption == "my finish"
      assert photo.bib_numbers == ["42"]
    end

    test "the submission does not join the public gallery", %{conn: conn} do
      {race, uploader} = setup_race()
      _pending = pending_photo_fixture(race, uploader)

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}/photos")

      assert html =~ "No photos yet"
    end

    test "is refused when the race closes to uploads mid-session", %{conn: conn} do
      {race, uploader} = setup_race()

      {:ok, view, _html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      render_click(view, "open_upload", %{})
      {:ok, _} = Bibtime.Races.update_race(race, %{photo_uploads_enabled: false})

      html = render_submit(view, "submit_photos", %{"caption" => "", "bib_numbers" => ""})

      assert html =~ "Photo uploads are not open for this race."
      refute html =~ "Add your photos"
      assert Photos.count_pending_photos(race.id) == 0
    end
  end

  describe "the uploader's own submissions" do
    test "are listed with a pending badge, invisible to others", %{conn: conn} do
      {race, uploader} = setup_race()
      pending_photo_fixture(race, uploader)

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      assert html =~ "Your submissions"
      assert html =~ "Pending review"

      {:ok, _view, other_html} =
        conn |> log_in_user(user_fixture()) |> live(~p"/races/#{race.slug}/photos")

      refute other_html =~ "Your submissions"
    end

    test "show the rejection reason", %{conn: conn} do
      {race, uploader} = setup_race()
      photo = pending_photo_fixture(race, uploader)
      {:ok, _} = Photos.reject_photo(photo, admin_user_fixture(), "Wrong race")

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      assert html =~ "Not published"
      assert html =~ "Wrong race"
    end

    test "drop off the list once approved and appear in the gallery", %{conn: conn} do
      {race, uploader} = setup_race()
      photo = pending_photo_fixture(race, uploader, %{bib_numbers: ["42"]})
      {:ok, _} = Photos.approve_photo(photo, admin_user_fixture())

      {:ok, _view, html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      refute html =~ "Your submissions"
      assert html =~ "1 photo"
    end

    test "can be withdrawn while pending", %{conn: conn} do
      {race, uploader} = setup_race()
      photo = pending_photo_fixture(race, uploader)

      {:ok, view, _html} =
        conn |> log_in_user(uploader) |> live(~p"/races/#{race.slug}/photos")

      html = render_click(view, "withdraw_photo", %{"id" => photo.id})

      assert html =~ "Photo withdrawn."
      refute html =~ "Your submissions"
      assert Photos.count_pending_photos(race.id) == 0
    end

    test "cannot be withdrawn by someone else", %{conn: conn} do
      {race, uploader} = setup_race()
      photo = pending_photo_fixture(race, uploader)

      other = user_fixture()
      participant_fixture(race, %{email: other.email})

      {:ok, view, _html} =
        conn |> log_in_user(other) |> live(~p"/races/#{race.slug}/photos")

      html = render_click(view, "withdraw_photo", %{"id" => photo.id})

      assert html =~ "Could not withdraw that photo."
      assert Photos.count_pending_photos(race.id) == 1
    end
  end

  describe "finding the gallery" do
    test "the race page links to photos once the race is under way", %{conn: conn} do
      {race, _uploader} = setup_race(%{status: :in_progress})

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}")

      assert html =~ ~p"/races/#{race.slug}/photos"
    end

    test "the race page links to an empty gallery too", %{conn: conn} do
      {race, _uploader} = setup_race()

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}")

      assert Photos.count_photos(race.id) == 0
      assert html =~ ~p"/races/#{race.slug}/photos"
    end

    test "the race page withholds the link before the race starts", %{conn: conn} do
      {race, _uploader} = setup_race(%{status: :registration_open})

      {:ok, _view, html} = live(conn, ~p"/races/#{race.slug}")

      refute html =~ ~p"/races/#{race.slug}/photos"
    end
  end

  describe "search" do
    test "only ever matches approved photos", %{conn: conn} do
      {race, uploader} = setup_race()
      photo_fixture(race, %{bib_numbers: ["42"], caption: "sprint"})
      pending_photo_fixture(race, uploader, %{bib_numbers: ["42"], caption: "sprint"})

      {:ok, view, _html} = live(conn, ~p"/races/#{race.slug}/photos")

      html = render_change(view, "search", %{"search" => "sprint"})

      assert html =~ "1 photo"
      refute html =~ "2 photos"
    end
  end
end
