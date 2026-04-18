defmodule Bibtime.RegistrationTest do
  use Bibtime.DataCase, async: true

  alias Bibtime.Registration
  alias Bibtime.Participants.Participant
  alias Bibtime.Races.{Race, RaceCategory}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_race!(status \\ :registration_open, opts \\ []) do
    Repo.insert!(%Race{
      name: "Reg Race",
      slug: "reg-race-#{System.unique_integer([:positive])}",
      race_type: :running,
      status: status,
      participant_limit: Keyword.get(opts, :participant_limit)
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
  # registration_full?/1
  # ---------------------------------------------------------------------------

  describe "registration_full?/1" do
    test "returns false when no participant_limit is set" do
      race = create_race!()
      insert_participant!(race, "1")
      assert Registration.registration_full?(race) == false
    end

    test "returns false when participant count is below limit" do
      race = create_race!(:registration_open, participant_limit: 3)
      insert_participant!(race, "1")
      assert Registration.registration_full?(race) == false
    end

    test "returns true when participant count equals limit" do
      race = create_race!(:registration_open, participant_limit: 2)
      insert_participant!(race, "1")
      insert_participant!(race, "2")
      assert Registration.registration_full?(race) == true
    end

    test "returns true when participant count exceeds limit" do
      race = create_race!(:registration_open, participant_limit: 1)
      insert_participant!(race, "1")
      insert_participant!(race, "2")
      assert Registration.registration_full?(race) == true
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

    test "fails when participant limit is reached" do
      race = create_race!(:registration_open, participant_limit: 1)
      category = create_category!(race)
      insert_participant!(race, "1")

      assert {:error, changeset} =
               Registration.register_participant(race, valid_attrs(category))

      assert %{base: ["Registration is full"]} = errors_on(changeset)
    end

    test "succeeds when participant limit is not yet reached" do
      race = create_race!(:registration_open, participant_limit: 5)
      category = create_category!(race)
      insert_participant!(race, "1")

      assert {:ok, %Participant{}} =
               Registration.register_participant(race, valid_attrs(category))
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

    test "allows registration without last_name" do
      race = create_race!()
      category = create_category!(race)
      attrs = valid_attrs(category) |> Map.delete(:last_name)

      assert {:ok, participant} = Registration.register_participant(race, attrs)
      assert participant.first_name == "Alice"
      assert participant.last_name == nil
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
