defmodule Bibtime.Races.RaceNotifierTest do
  use Bibtime.DataCase, async: true

  import Bibtime.RacesFixtures
  import Bibtime.ParticipantsFixtures

  alias Bibtime.Accounts.User
  alias Bibtime.Races.RaceNotifier
  alias Bibtime.Repo

  @subject "Start PM and race-day info"
  @body "The Start PM is published: https://example.com/start-pm.pdf"

  defp race! do
    race_fixture(%{
      status: :registration_closed,
      name: "Klagshamn Triathlon",
      date: ~D[2026-09-05],
      location: "Klagshamn"
    })
  end

  # Participants only have an address by way of a linked user account — the
  # user record is the single source of truth for email.
  defp with_email(participant, email, opts \\ []) do
    user =
      Repo.insert!(%User{email: email, preferred_locale: Keyword.get(opts, :locale)})

    participant
    |> Ecto.Changeset.change(user_id: user.id)
    |> Repo.update!()
    |> Repo.preload(:user)
  end

  defp with_token(participant, token) do
    participant
    |> Ecto.Changeset.change(confirmation_token: token)
    |> Repo.update!()
  end

  # Bulk sends go through deliver_many, which the Swoosh test adapter reports
  # as a single {:emails, list} message rather than one {:email, _} apiece.
  defp sent_emails(acc \\ []) do
    receive do
      {:emails, emails} -> sent_emails(acc ++ emails)
      {:email, email} -> sent_emails(acc ++ [email])
    after
      0 -> acc
    end
  end

  defp recipients_of(emails) do
    Enum.flat_map(emails, fn email -> Enum.map(email.to, fn {_name, addr} -> addr end) end)
  end

  describe "recipients/2" do
    test "separates participants with an address from those without" do
      race = race!()

      with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")
      # CSV-imported participants deliberately have no user account.
      participant_fixture(race, %{bib_number: "2"})

      %{deliverable: deliverable, missing_email: missing} = RaceNotifier.recipients(race.id)

      assert Enum.map(deliverable, & &1.bib_number) == ["1"]
      assert Enum.map(missing, & &1.bib_number) == ["2"]
    end

    test "excludes unpaid registrations by default" do
      race = race!()

      with_email(
        participant_fixture(race, %{bib_number: "1", status: :pending_payment}),
        "unpaid@example.com"
      )

      with_email(participant_fixture(race, %{bib_number: "2"}), "paid@example.com")

      assert %{deliverable: [only]} = RaceNotifier.recipients(race.id)
      assert only.bib_number == "2"
    end

    test "includes unpaid registrations when opted in" do
      race = race!()

      with_email(
        participant_fixture(race, %{bib_number: "1", status: :pending_payment}),
        "unpaid@example.com"
      )

      with_email(participant_fixture(race, %{bib_number: "2"}), "paid@example.com")

      %{deliverable: deliverable} =
        RaceNotifier.recipients(race.id, include_pending_payment: true)

      assert Enum.map(deliverable, & &1.bib_number) == ["1", "2"]
    end
  end

  describe "email_announcement/4" do
    test "sends the organizer's subject and body verbatim" do
      race = race!()
      p = with_email(participant_fixture(race, %{bib_number: "42"}), "runner@example.com")

      email = RaceNotifier.email_announcement(p, race, @subject, @body)

      assert email.subject == @subject
      assert email.text_body =~ @body
      assert email.to == [{"", "runner@example.com"}]
    end

    test "frames the message with the participant's own bib and race details" do
      race = race!()
      p = with_email(participant_fixture(race, %{bib_number: "42"}), "runner@example.com")

      email = RaceNotifier.email_announcement(p, race, @subject, @body)

      assert email.text_body =~ "Hi #{p.first_name},"
      assert email.text_body =~ "Your bib number: 42"
      assert email.text_body =~ "Klagshamn Triathlon"
      assert email.text_body =~ "Klagshamn"
    end

    test "links to the participant's own registration when they have a token" do
      race = race!()

      p =
        race
        |> participant_fixture(%{bib_number: "42"})
        |> with_token("SECRET_TOKEN")
        |> with_email("runner@example.com")

      email = RaceNotifier.email_announcement(p, race, @subject, @body)

      assert email.text_body =~ "/races/#{race.slug}/my-registration/SECRET_TOKEN"
    end

    test "falls back to the race page when the participant has no token" do
      race = race!()
      p = with_email(participant_fixture(race, %{bib_number: "7"}), "runner@example.com")

      email = RaceNotifier.email_announcement(p, race, @subject, @body)

      refute email.text_body =~ "/my-registration/"
      assert email.text_body =~ "/races/#{race.slug}"
    end

    test "renders the frame in each recipient's own locale" do
      race = race!()

      sv =
        with_email(participant_fixture(race, %{bib_number: "1"}), "sv@example.com", locale: "sv")

      en =
        with_email(participant_fixture(race, %{bib_number: "2"}), "en@example.com", locale: "en")

      sv_email = RaceNotifier.email_announcement(sv, race, @subject, @body)
      en_email = RaceNotifier.email_announcement(en, race, @subject, @body)

      assert sv_email.text_body =~ "Ditt startnummer: 1"
      assert en_email.text_body =~ "Your bib number: 2"

      # The organizer's own words are untouched in both.
      assert sv_email.text_body =~ @body
      assert en_email.text_body =~ @body
    end

    test "sends from the configured address under the site name" do
      race = race!()
      p = with_email(participant_fixture(race, %{bib_number: "1"}), "runner@example.com")

      email = RaceNotifier.email_announcement(p, race, @subject, @body)

      # The whole field is mailed from the app's own verified sender, never
      # from an organizer address on some unverified domain.
      expected = Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
      assert email.from == {Bibtime.SiteSettings.get().site_name, expected}
    end
  end

  describe "deliver_announcement/4" do
    test "delivers to everyone reachable and reports the counts" do
      race = race!()
      with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")
      with_email(participant_fixture(race, %{bib_number: "2"}), "two@example.com")
      participant_fixture(race, %{bib_number: "3"})

      assert {:ok, result} = RaceNotifier.deliver_announcement(race, @subject, @body)

      assert result == %{sent: 2, failed: 0, skipped: 1}
      assert Enum.sort(recipients_of(sent_emails())) == ["one@example.com", "two@example.com"]
    end

    test "chunks sends to the provider's batch limit" do
      race = race!()
      count = RaceNotifier.batch_size() + 5

      for n <- 1..count do
        with_email(participant_fixture(race, %{bib_number: "#{n}"}), "runner#{n}@example.com")
      end

      assert {:ok, %{sent: ^count, failed: 0}} =
               RaceNotifier.deliver_announcement(race, @subject, @body)

      # Every recipient still gets exactly one email despite the chunking.
      addresses = recipients_of(sent_emails())
      assert length(addresses) == count
      assert length(Enum.uniq(addresses)) == count
    end

    test "records the send in the audit log" do
      race = race!()
      with_email(participant_fixture(race, %{bib_number: "1"}), "one@example.com")
      admin = Repo.insert!(%User{email: "admin@example.com"})

      {:ok, _} = RaceNotifier.deliver_announcement(race, @subject, @body, actor: admin)

      entry = Bibtime.AuditLog.list_entries(limit: 1) |> hd()

      assert entry.action == "race_announcement_sent"
      assert entry.resource_type == "race"
      assert entry.resource_id == race.id
      assert entry.user_id == admin.id
      assert entry.metadata["subject"] == @subject
      assert entry.metadata["sent"] == 1
      assert entry.metadata["skipped"] == 0
    end

    test "sends nothing when no participant has an address" do
      race = race!()
      participant_fixture(race, %{bib_number: "1"})

      assert {:ok, %{sent: 0, failed: 0, skipped: 1}} =
               RaceNotifier.deliver_announcement(race, @subject, @body)

      assert sent_emails() == []
    end

    test "does not reach participants in another race" do
      race = race!()
      other = race!()

      with_email(participant_fixture(race, %{bib_number: "1"}), "mine@example.com")
      with_email(participant_fixture(other, %{bib_number: "1"}), "theirs@example.com")

      {:ok, %{sent: 1}} = RaceNotifier.deliver_announcement(race, @subject, @body)

      assert recipients_of(sent_emails()) == ["mine@example.com"]
    end
  end

  describe "deliver_test/5" do
    test "sends a single copy to the given address" do
      race = race!()
      with_email(participant_fixture(race, %{bib_number: "1"}), "runner@example.com")

      assert {:ok, "admin@example.com"} =
               RaceNotifier.deliver_test(race, @subject, @body, "admin@example.com")

      assert [email] = sent_emails()
      assert email.to == [{"", "admin@example.com"}]
      assert email.text_body =~ @body
    end

    test "omits the bib line for the stand-in recipient" do
      race = race!()

      {:ok, _} = RaceNotifier.deliver_test(race, @subject, @body, "admin@example.com")

      assert [email] = sent_emails()
      refute email.text_body =~ "Your bib number"
      assert email.text_body =~ "/races/#{race.slug}"
    end

    test "honours the requested locale" do
      race = race!()

      {:ok, _} = RaceNotifier.deliver_test(race, @subject, @body, "admin@example.com", "sv")

      assert [email] = sent_emails()
      assert email.text_body =~ "Hej"
    end
  end
end
