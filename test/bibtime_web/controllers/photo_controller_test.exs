defmodule BibtimeWeb.PhotoControllerTest do
  use BibtimeWeb.ConnCase

  import Bibtime.AccountsFixtures
  import Bibtime.ParticipantsFixtures
  import Bibtime.PhotosFixtures
  import Bibtime.RacesFixtures

  setup do
    race = race_fixture(%{status: :finished, photos_public: true})
    uploader = user_fixture()
    participant_fixture(race, %{email: uploader.email})

    %{race: race, uploader: uploader}
  end

  describe "approved photos" do
    test "are served to anyone on a public-photo race", %{conn: conn, race: race} do
      photo = stored_photo_fixture(race)

      conn = get(conn, ~p"/photos/#{photo.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "image/jpeg"
    end

    test "are withheld on a participants-only race", %{conn: conn} do
      race = race_fixture(%{status: :finished, photos_public: false})
      photo = stored_photo_fixture(race)

      conn = get(conn, ~p"/photos/#{photo.id}")

      assert conn.status == 404
    end

    test "404 when the stored file is gone", %{conn: conn, race: race} do
      photo = photo_fixture(race, %{file_path: "races/#{race.id}/photos/missing.jpg"})

      assert get(conn, ~p"/photos/#{photo.id}").status == 404
    end
  end

  describe "pending photos" do
    setup %{race: race, uploader: uploader} do
      {:ok, photo} =
        Bibtime.Photos.submit_photo(race, uploader, upload_entry(), image_file(:jpeg), %{})

      %{photo: photo}
    end

    test "are not served to anonymous visitors", %{conn: conn, photo: photo} do
      assert get(conn, ~p"/photos/#{photo.id}").status == 404
    end

    test "are not served to another logged-in participant", %{
      conn: conn,
      race: race,
      photo: photo
    } do
      other = user_fixture()
      participant_fixture(race, %{email: other.email})

      conn = conn |> log_in_user(other) |> get(~p"/photos/#{photo.id}")

      assert conn.status == 404
    end

    test "are served to the uploader, uncacheable", %{conn: conn, photo: photo, uploader: user} do
      conn = conn |> log_in_user(user) |> get(~p"/photos/#{photo.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "are served to an admin", %{conn: conn, photo: photo} do
      conn = conn |> log_in_user(admin_user_fixture()) |> get(~p"/photos/#{photo.id}")

      assert conn.status == 200
    end

    test "become public once approved", %{conn: conn, photo: photo} do
      {:ok, _} = Bibtime.Photos.approve_photo(photo, admin_user_fixture())

      conn = get(conn, ~p"/photos/#{photo.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["private, max-age=270"]
    end
  end

  describe "static file serving" do
    test "the uploads directory is no longer exposed by Plug.Static", %{conn: conn} do
      refute "uploads" in BibtimeWeb.static_paths()

      assert get(conn, "/uploads/races/1/photos/anything.jpg").status == 404
    end
  end
end
