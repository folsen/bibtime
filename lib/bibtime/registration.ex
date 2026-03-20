defmodule Bibtime.Registration do
  @moduledoc """
  The Registration context.

  Handles public participant registration for races.
  Creates a user account if one doesn't exist for the participant's email.
  """

  alias Bibtime.Repo
  alias Bibtime.Accounts
  alias Bibtime.Participants
  alias Bibtime.Participants.Participant
  alias Bibtime.Registration.RegistrationNotifier

  @doc """
  Returns true if the race's status is :registration_open.
  """
  def registration_open?(%{status: :registration_open}), do: true
  def registration_open?(_race), do: false

  @doc """
  Registers a participant for a race.

  Auto-assigns a bib number, generates a confirmation token, and creates
  a user account (if one doesn't exist) linked to the participant.

  Returns {:ok, participant} or {:error, changeset}.
  """
  def register_participant(race, attrs) do
    if registration_open?(race) do
      bib_number = Participants.next_bib_number(race.id)
      token = generate_token()

      changeset =
        %Participant{race_id: race.id, bib_number: bib_number, confirmation_token: token}
        |> Participant.registration_changeset(attrs)

      email = Ecto.Changeset.get_change(changeset, :email) || Ecto.Changeset.get_field(changeset, :email)

      case Repo.insert(changeset) do
        {:ok, participant} ->
          # Find or create a user account for this email
          user = find_or_create_user(email)

          if user do
            participant
            |> Ecto.Changeset.change(%{user_id: user.id})
            |> Repo.update!()
          end

          participant = Repo.preload(participant, :race_category)
          RegistrationNotifier.deliver_confirmation(participant, race)
          {:ok, participant}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error,
       %Participant{}
       |> Participant.registration_changeset(attrs)
       |> Ecto.Changeset.add_error(:base, "Registration is not open for this race")}
    end
  end

  @doc """
  Returns a changeset for the registration form.
  """
  def change_registration(%Participant{} = participant, attrs \\ %{}) do
    Participant.registration_changeset(participant, attrs)
  end

  defp find_or_create_user(nil), do: nil

  defp find_or_create_user(email) do
    case Accounts.get_user_by_email(email) do
      %{} = user ->
        user

      nil ->
        case Accounts.register_user(%{email: email}) do
          {:ok, user} -> user
          {:error, _} -> nil
        end
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
