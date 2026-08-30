defmodule Bibtime.Photos.PhotoNotifier do
  @moduledoc """
  Emails around participant photo submissions.

  Three messages, all plain text and all batched by intent rather than by row:
  organizers hear once per submission batch, and an uploader hears once per
  review action. Approving twenty photos at once must not send twenty emails.
  """

  import Swoosh.Email
  use Gettext, backend: BibtimeWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: BibtimeWeb.Endpoint,
    router: BibtimeWeb.Router,
    statics: BibtimeWeb.static_paths()

  alias Bibtime.Mailer
  alias Bibtime.SiteSettings

  @doc """
  Notice to an organizer that photos are waiting in the review queue.
  """
  def email_pending_review(admin, race, count) do
    Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(admin), fn ->
      build_email(
        admin.email,
        ngettext(
          "%{count} photo awaiting review",
          "%{count} photos awaiting review",
          count
        ) <> " — #{race.name}",
        """
        #{ngettext("A participant submitted %{count} photo for %{race}.", "A participant submitted %{count} photos for %{race}.", count, race: race.name)}

        #{gettext("Review them here:")}
        #{url(~p"/admin/races/#{race.id}/photos?#{[status: "pending"]}")}

        #{gettext("Photos stay hidden from the gallery until you approve them.")}
        """
      )
    end)
  end

  @doc """
  Notice to an uploader that their submission is now public.
  """
  def email_photos_approved(user, race, count) do
    Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(user), fn ->
      build_email(
        user.email,
        ngettext("Your photo is published", "Your photos are published", count) <>
          " — #{race.name}",
        """
        #{ngettext("Thanks! %{count} of your photos from %{race} has been approved and is now in the race gallery.", "Thanks! %{count} of your photos from %{race} have been approved and are now in the race gallery.", count, race: race.name)}

        #{gettext("See the gallery:")}
        #{url(~p"/races/#{race.slug}/photos")}
        """
      )
    end)
  end

  @doc """
  Notice to an uploader that a submission will not be published.
  """
  def email_photo_rejected(user, race, reason) do
    Gettext.with_locale(BibtimeWeb.Gettext, SiteSettings.locale_for(user), fn ->
      reason_line =
        if reason do
          "\n#{gettext("Reason given")}: #{reason}\n"
        else
          ""
        end

      build_email(
        user.email,
        gettext("A photo you submitted was not published") <> " — #{race.name}",
        """
        #{gettext("One of the photos you submitted for %{race} will not be added to the gallery.", race: race.name)}
        #{reason_line}
        #{gettext("You can still submit other photos:")}
        #{url(~p"/races/#{race.slug}/photos")}
        """
      )
    end)
  end

  @doc """
  Sends the pending-review notice to every admin.
  """
  def deliver_pending_review_notice(race, count) when count > 0 do
    Bibtime.Accounts.list_admins()
    |> Enum.map(&email_pending_review(&1, race, count))
    |> deliver_async()
  end

  def deliver_pending_review_notice(_race, _count), do: :ok

  def deliver_photos_approved(user, race, count) when count > 0 do
    [email_photos_approved(user, race, count)] |> deliver_async()
  end

  def deliver_photos_approved(_user, _race, _count), do: :ok

  def deliver_photo_rejected(user, race, reason) do
    [email_photo_rejected(user, race, reason)] |> deliver_async()
  end

  @doc """
  Delivers already-built emails off the caller's process.

  Emails are composed by the caller — which is inside the Ecto sandbox during
  tests and has the settings cache warm — so the supervised task only performs
  network I/O and never touches the database.
  """
  def deliver_async([]), do: :ok

  def deliver_async(emails) do
    Task.Supervisor.start_child(Bibtime.TaskSupervisor, fn ->
      require Logger

      Enum.each(emails, fn email ->
        try do
          deliver(email)
        rescue
          e -> Logger.error("Photo notification email failed: #{inspect(e)}")
        end
      end)
    end)

    :ok
  end

  defp build_email(recipient, subject, body) do
    new()
    |> to(recipient)
    |> from({SiteSettings.get().site_name, from_address()})
    |> subject(subject)
    |> text_body(body)
  end

  defp from_address do
    Application.get_env(:bibtime, :mailer_from_address, "contact@example.com")
  end

  defp deliver(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
