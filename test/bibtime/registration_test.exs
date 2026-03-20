defmodule Bibtime.RegistrationTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Registration
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.{Race, RaceCategory}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race!(status \\ :registration_open) do
    Repo.insert!(%Race{
      name: "Reg Race",
      slug: "reg-race-#{System.unique_integer([:positive])}",
      race_type: :running,
      status: status
    })
  end

  defp create_category!(race, name \\ "Open") do
    Repo.insert!(%RaceCategory{
      name: name,
      race_id: race.id
    })
  end

  defp valid_attrs(category) do
    %{
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      race_category_id: category.id
    }
  end

  defp insert_participant!(race, bib_number) do
    Repo.insert!(%Participant{
      bib_number: bib_number,
      first_name: "Existing",
      last_name: "Runner",
      race_id: race.id
    })
  end

  # ---------------------------------------------------------------------------
  # registration_open?/1
  # ---------------------------------------------------------------------------

  describe "registration_open?/1" do
    test "returns true when race status is :registration_open" do
      race = create_race!(:registration_open)
      assert Registration.registration_open?(race) == true
    end

    test "returns false when race status is :draft" do
      race = create_race!(:draft)
      assert Registration.registration_open?(race) == false
    end

    test "returns false when race status is :in_progress" do
      race = create_race!(:in_progress)
      assert Registration.registration_open?(race) == false
    end

    test "returns false when race status is :registration_closed" do
      race = create_race!(:registration_closed)
      assert Registration.registration_open?(race) == false
    end

    test "returns false when race status is :finished" do
      race = create_race!(:finished)
      assert Registration.registration_open?(race) == false
    end
  end

  # ---------------------------------------------------------------------------
  # register_participant/2
  # ---------------------------------------------------------------------------

  describe "register_participant/2" do
    test "succeeds with valid attrs when race status is :registration_open" do
      race = create_race!(:registration_open)
      category = create_category!(race)

      assert {:ok, %Participant{} = participant} =
               Registration.register_participant(race, valid_attrs(category))

      assert participant.first_name == "Alice"
      assert participant.last_name == "Smith"
      assert participant.email == "alice@example.com"
      assert participant.race_id == race.id
      assert participant.race_category_id == category.id
      assert participant.status == :registered
    end

    test "fails when race status is :draft" do
      race = create_race!(:draft)
      category = create_category!(race)

      assert {:error, changeset} =
               Registration.register_participant(race, valid_attrs(category))

      assert %{base: ["Registration is not open for this race"]} = errors_on(changeset)
    end

    test "fails when race status is :in_progress" do
      race = create_race!(:in_progress)
      category = create_category!(race)

      assert {:error, changeset} =
               Registration.register_participant(race, valid_attrs(category))

      assert %{base: ["Registration is not open for this race"]} = errors_on(changeset)
    end

    # -------------------------------------------------------------------------
    # Auto bib number assignment
    # -------------------------------------------------------------------------

    test "first participant gets bib number \"1\"" do
      race = create_race!()
      category = create_category!(race)

      {:ok, participant} = Registration.register_participant(race, valid_attrs(category))

      assert participant.bib_number == "1"
    end

    test "second participant gets bib number \"2\"" do
      race = create_race!()
      category = create_category!(race)

      {:ok, p1} = Registration.register_participant(race, valid_attrs(category))
      assert p1.bib_number == "1"

      {:ok, p2} =
        Registration.register_participant(race, %{
          first_name: "Bob",
          last_name: "Jones",
          email: "bob@example.com",
          race_category_id: category.id
        })

      assert p2.bib_number == "2"
    end

    test "auto bib number picks up from existing participants" do
      race = create_race!()
      category = create_category!(race)

      # Pre-populate bibs 1 through 5
      for i <- 1..5, do: insert_participant!(race, "#{i}")

      {:ok, participant} = Registration.register_participant(race, valid_attrs(category))

      assert participant.bib_number == "6"
    end

    # -------------------------------------------------------------------------
    # Validation: required fields
    # -------------------------------------------------------------------------

    test "requires first_name" do
      race = create_race!()
      category = create_category!(race)
      attrs = valid_attrs(category) |> Map.delete(:first_name)

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{first_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires last_name" do
      race = create_race!()
      category = create_category!(race)
      attrs = valid_attrs(category) |> Map.delete(:last_name)

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{last_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires email" do
      race = create_race!()
      category = create_category!(race)
      attrs = valid_attrs(category) |> Map.delete(:email)

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires race_category_id" do
      race = create_race!()
      _category = create_category!(race)
      attrs = valid_attrs(%{id: nil}) |> Map.delete(:race_category_id)

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{race_category_id: ["can't be blank"]} = errors_on(changeset)
    end

    # -------------------------------------------------------------------------
    # Email format validation
    # -------------------------------------------------------------------------

    test "validates email format - rejects missing @" do
      race = create_race!()
      category = create_category!(race)
      attrs = %{valid_attrs(category) | email: "not-an-email"}

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end

    test "validates email format - rejects missing domain" do
      race = create_race!()
      category = create_category!(race)
      attrs = %{valid_attrs(category) | email: "user@"}

      assert {:error, changeset} = Registration.register_participant(race, attrs)
      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end

    # -------------------------------------------------------------------------
    # Confirmation token
    # -------------------------------------------------------------------------

    test "generates a confirmation_token for each registration" do
      race = create_race!()
      category = create_category!(race)

      {:ok, participant} = Registration.register_participant(race, valid_attrs(category))

      assert participant.confirmation_token != nil
      assert is_binary(participant.confirmation_token)
      assert String.length(participant.confirmation_token) > 0
    end

    test "each registration gets a unique confirmation_token" do
      race = create_race!()
      category = create_category!(race)

      {:ok, p1} = Registration.register_participant(race, valid_attrs(category))

      {:ok, p2} =
        Registration.register_participant(race, %{
          first_name: "Bob",
          last_name: "Jones",
          email: "bob@example.com",
          race_category_id: category.id
        })

      assert p1.confirmation_token != p2.confirmation_token
    end
  end
end
