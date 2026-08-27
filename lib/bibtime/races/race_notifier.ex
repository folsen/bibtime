defmodule Bibtime.Races.RaceNotifier do
  @moduledoc """
  Announcement email sent from the admin race page to every participant in a
  race — a pre-race reminder linking to the Start PM, a "results are up"
  notice, and so on.

  Unlike the transactional notifiers this fans out to a whole start list, so
  delivery goes through the mailer's batch API (`deliver_many/1`) in chunks of
  100 rather than one request per recipient, which would trip the provider's
  rate limit on a field of any size.

  The organizer writes the subject and body once, in one language. Those go out
  verbatim; only the frame around them (greeting, bib number, links) is
  rendered in each recipient's own locale.
  """

  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: BibtimeWeb.Endpoint,
    router: BibtimeWeb.Router,
    statics: BibtimeWeb.static_paths()

  alias Bibtime.Accounts.User
  alias Bibtime.AuditLog
  alias Bibtime.Mailer
  alias Bibtime.Participants
  alias Bibtime.Participants.Participant
  alias Bibtime.SiteSettings
  alias BibtimeWeb.LocaleHelpers

  # Resend's batch endpoint caps a request at 100 emails.
  @batch_size 100

  # Participants who never completed payment are not on the start list, so they
  # are excluded unless the organizer opts in.
  @default_statuses [:registered, :checked_in, :racing, :dns, :dnf, :dsq, :finished]
  @opt_in_statuses [:pending_payment]

  def default_statuses, do: @default_statuses
  def opt_in_statuses, do: @opt_in_statuses
  def batch_size, do: @batch_size

  @doc """
  Splits a race's participants into those an announcement can reach and those
  it cannot.

  A participant has no address when they have no linked user account — CSV
  imports of historic results deliberately create participants that way.

  Pass `include_pending_payment: true` to add registrations that never
  completed checkout.
  """
  def recipients(race_id, opts \\ []) do
    {deliverable, missing_email} =
      race_id
      |> Participants.list_participants_by_status(statuses_for(opts))
      |> Enum.split_with(&(recipient_email(&1) != nil))

    %{deliverable: deliverable, missing_email: missing_email}
  end

  @doc """
  Builds the announcement email for one participant (also used by previews).

  `subject` and `body` are the organizer's own words and are inserted as
  written.
  """
  def email_announcement(participant, race, subject, body) do
    locale = SiteSettings.locale_for(Map.get(participant, :user))

    Gettext.with_locale(BibtimeWeb.Gettext, locale, fn ->
      new()
      |> to(recipient_email(participant))
      |> from({SiteSettings.get().site_name, from_address()})
      |> subject(subject)
      |> text_body(framed_body(participant, race, body))
    end)
  end

  @doc """
  Sends the announcement to every reachable participant in the race.

  Returns `{:ok, %{sent: n, failed: n, skipped: n}}`. Delivery is per-chunk, so
  a provider error fails that chunk's recipients and leaves the rest sent — the
  counts report what actually happened rather than raising on partial success.

  Options:
    * `:include_pending_payment` — see `recipients/2`
    * `:actor` — the admin user, recorded in the audit log
  """
  def deliver_announcement(race, subject, body, opts \\ []) do
    %{deliverable: deliverable, missing_email: missing_email} = recipients(race.id, opts)

    # One reference per send, so a double-submit is deduplicated by the provider
    # rather than mailing the whole start list twice.
    send_ref = Ecto.UUID.generate()

    {sent, failed} =
      deliverable
      |> Enum.chunk_every(@batch_size)
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {chunk, idx}, {sent, failed} ->
        emails =
          Enum.map(chunk, fn participant ->
            participant
            |> email_announcement(race, subject, body)
            |> put_provider_option(:idempotency_key, "#{send_ref}-#{idx}")
          end)

        case Mailer.deliver_many(emails) do
          {:ok, _} -> {sent + length(chunk), failed}
          {:error, _reason} -> {sent, failed + length(chunk)}
        end
      end)

    result = %{sent: sent, failed: failed, skipped: length(missing_email)}

    AuditLog.log(opts[:actor], "race_announcement_sent", "race", race.id, %{
      "subject" => subject,
      "sent" => sent,
      "failed" => failed,
      "skipped" => result.skipped,
      "send_ref" => send_ref
    })

    {:ok, result}
  end

  @doc """
  Sends a single copy of the announcement to `email`, so the organizer can read
  the real thing before mailing the field.

  Addressed to a stand-in participant, since the admin is not necessarily
  registered for the race they are announcing.
  """
  def deliver_test(race, subject, body, email, locale \\ nil) do
    user = %User{email: email, preferred_locale: locale}

    stand_in =
      Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(user), fn ->
        %Participant{first_name: gettext("there"), user: user}
      end)

    case stand_in |> email_announcement(race, subject, body) |> Mailer.deliver() do
      {:ok, _metadata} -> {:ok, email}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp statuses_for(opts) do
    if Keyword.get(opts, :include_pending_payment, false),
      do: @default_statuses ++ @opt_in_statuses,
      else: @default_statuses
  end

  defp framed_body(participant, race, body) do
    """
    #{gettext("Hi %{name},", name: participant.first_name)}

    #{String.trim(body)}

    --
    #{race_footer(participant, race)}
    """
  end

  defp race_footer(participant, race) do
    [
      race.name,
      race.date && LocaleHelpers.format_date(race.date),
      race.location,
      participant.bib_number && gettext("Your bib number: %{bib}", bib: participant.bib_number),
      registration_link(participant, race)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp registration_link(%{confirmation_token: token}, race) when is_binary(token) do
    gettext("Your registration:") <> "\n" <> url(~p"/races/#{race.slug}/my-registration/#{token}")
  end

  defp registration_link(_participant, race) do
    gettext("Race page:") <> "\n" <> url(~p"/races/#{race.slug}")
  end

  defp recipient_email(participant) do
    case Map.get(participant, :user) do
      %{email: email} when is_binary(email) and email != "" -> email
      _ -> nil
    end
  end

  defp from_address do
    Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
  end
end
