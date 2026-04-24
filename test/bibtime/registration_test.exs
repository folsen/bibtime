defmodule Bibtime.RegistrationTest do
  use Bibtime.DataCase, async: true

  import Ecto.Query

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

    # -------------------------------------------------------------------------
    # Duplicate-registration block (same race + email + first + last)
    # -------------------------------------------------------------------------

    test "blocks an exact duplicate (same name + email + race)" do
      race = create_race!()
      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))

      assert {:error, :duplicate, existing} =
               Registration.register_participant(race, valid_attrs(category))

      assert existing.id == first.id
    end

    test "duplicate detection is case-insensitive and trims whitespace" do
      race = create_race!()
      category = create_category!(race)

      {:ok, _} = Registration.register_participant(race, valid_attrs(category))

      attrs = %{
        first_name: "  ALICE ",
        last_name: "smith",
        email: "ALICE@Example.com",
        race_category_id: category.id
      }

      assert {:error, :duplicate, _} = Registration.register_participant(race, attrs)
    end

    test "allows same email with a different name (e.g. registering a spouse)" do
      race = create_race!()
      category = create_category!(race)

      {:ok, _} = Registration.register_participant(race, valid_attrs(category))

      spouse_attrs = %{
        first_name: "Bob",
        last_name: "Smith",
        email: "alice@example.com",
        race_category_id: category.id
      }

      assert {:ok, %Participant{first_name: "Bob"}} =
               Registration.register_participant(race, spouse_attrs)
    end

    test "allows the same name+email across different races" do
      race1 = create_race!()
      race2 = create_race!()
      category1 = create_category!(race1)
      category2 = create_category!(race2)

      {:ok, _} = Registration.register_participant(race1, valid_attrs(category1))

      assert {:ok, %Participant{}} =
               Registration.register_participant(race2, valid_attrs(category2))
    end

    test "duplicate check does not short-circuit regular validation errors" do
      race = create_race!()
      _category = create_category!(race)
      # Missing email — should still return a changeset error, not a duplicate tuple
      attrs = %{first_name: "Alice", last_name: "Smith"}

      assert {:error, %Ecto.Changeset{}} = Registration.register_participant(race, attrs)
    end

    # -------------------------------------------------------------------------
    # Resume of a pending paid registration
    # -------------------------------------------------------------------------

    test "resubmitting a :pending_payment registration returns the same participant" do
      race =
        Repo.insert!(%Race{
          name: "Paid Race",
          slug: "paid-race-#{System.unique_integer([:positive])}",
          race_type: :running,
          status: :registration_open,
          payment_required: true,
          entry_fee_cents: 10_000,
          currency: "SEK"
        })

      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))
      assert first.status == :pending_payment

      assert {:ok, %Participant{} = second} =
               Registration.register_participant(race, valid_attrs(category))

      assert second.id == first.id
      assert second.bib_number == first.bib_number
      assert second.confirmation_token == first.confirmation_token
      assert second.status == :pending_payment
    end

    test "resuming a pending registration applies edited form fields" do
      race =
        Repo.insert!(%Race{
          name: "Paid Race",
          slug: "paid-race-#{System.unique_integer([:positive])}",
          race_type: :running,
          status: :registration_open,
          payment_required: true,
          entry_fee_cents: 10_000,
          currency: "SEK"
        })

      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))

      edited_attrs = Map.merge(valid_attrs(category), %{club: "New Club"})

      assert {:ok, %Participant{} = second} =
               Registration.register_participant(race, edited_attrs)

      assert second.id == first.id
      assert second.club == "New Club"
    end

    test "still blocks duplicates whose status is past pending_payment" do
      race = create_race!()
      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))
      # Free-race registrations land at :registered immediately
      assert first.status == :registered

      assert {:error, :duplicate, existing} =
               Registration.register_participant(race, valid_attrs(category))

      assert existing.id == first.id
    end
  end

  # ---------------------------------------------------------------------------
  # Hold-based flow for paid races (bib assigned at payment, not registration)
  # ---------------------------------------------------------------------------

  describe "paid-race registration" do
    defp create_paid_race!(opts \\ []) do
      Repo.insert!(%Race{
        name: "Paid Race",
        slug: "paid-race-#{System.unique_integer([:positive])}",
        race_type: :running,
        status: :registration_open,
        payment_required: true,
        entry_fee_cents: 10_000,
        currency: "SEK",
        participant_limit: Keyword.get(opts, :participant_limit)
      })
    end

    test "new registration on a paid race has no bib and an active hold" do
      race = create_paid_race!()
      category = create_category!(race)

      {:ok, participant} = Registration.register_participant(race, valid_attrs(category))

      assert participant.status == :pending_payment
      assert is_nil(participant.bib_number)
      assert participant.hold_expires_at
      assert DateTime.compare(participant.hold_expires_at, DateTime.utc_now()) == :gt
    end

    test "resume refreshes a lapsed hold back into the future" do
      race = create_paid_race!()
      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))

      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      Repo.update_all(
        from(p in Participant, where: p.id == ^first.id),
        set: [hold_expires_at: past]
      )

      {:ok, resumed} = Registration.register_participant(race, valid_attrs(category))

      assert resumed.id == first.id
      assert DateTime.compare(resumed.hold_expires_at, DateTime.utc_now()) == :gt
      # Fresh expiry should be within a few seconds of now + hold_ttl.
      expected = DateTime.add(DateTime.utc_now(), Registration.hold_ttl_seconds(), :second)
      diff = DateTime.diff(expected, resumed.hold_expires_at, :second)
      assert abs(diff) <= 5
    end

    test "resume attempt is blocked when the race has filled during a lapsed hold" do
      race = create_paid_race!(participant_limit: 1)
      category = create_category!(race)

      {:ok, first} = Registration.register_participant(race, valid_attrs(category))

      Repo.update_all(
        from(p in Participant, where: p.id == ^first.id),
        set: [hold_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      {:ok, _other} =
        Registration.register_participant(race, %{
          first_name: "Bob",
          last_name: "Jones",
          email: "bob@example.com",
          race_category_id: category.id
        })

      # Top-level registration_full? fires before the duplicate check and
      # returns a generic changeset error — same user-facing message a brand
      # new user would get.
      assert {:error, %Ecto.Changeset{} = cs} =
               Registration.register_participant(race, valid_attrs(category))

      assert {"Registration is full", _} = cs.errors[:base]
    end
  end

  # ---------------------------------------------------------------------------
  # Capacity counting — holds count, lapsed holds don't
  # ---------------------------------------------------------------------------

  describe "registration_full?/1 with holds" do
    test "includes active holds in the slot count" do
      race = create_paid_race!(participant_limit: 1)
      category = create_category!(race)

      {:ok, _held} = Registration.register_participant(race, valid_attrs(category))

      assert Registration.registration_full?(race) == true
    end

    test "excludes lapsed holds from the slot count" do
      race = create_paid_race!(participant_limit: 1)
      category = create_category!(race)

      {:ok, held} = Registration.register_participant(race, valid_attrs(category))

      Repo.update_all(
        from(p in Participant, where: p.id == ^held.id),
        set: [hold_expires_at: DateTime.add(DateTime.utc_now(), -60, :second)]
      )

      assert Registration.registration_full?(race) == false
    end
  end
end
