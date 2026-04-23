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
  Returns true if the race has a participant limit and it has been reached.
  """
  def registration_full?(%{participant_limit: nil}), do: false

  def registration_full?(%{participant_limit: limit, id: race_id}) do
    Participants.count_participants(race_id) >= limit
  end

  @doc """
  Registers a participant for a race.

  Auto-assigns a bib number, generates a confirmation token, and creates
  a user account (if one doesn't exist) linked to the participant.

  Returns {:ok, participant} or {:error, changeset}.
  """
  def register_participant(race, attrs) do
    cond do
      not registration_open?(race) ->
        {:error,
         %Participant{}
         |> Participant.registration_changeset(attrs)
         |> Ecto.Changeset.add_error(:base, "Registration is not open for this race")}

      registration_full?(race) ->
        {:error,
         %Participant{}
         |> Participant.registration_changeset(attrs)
         |> Ecto.Changeset.add_error(:base, "Registration is full")}

      true ->
        bib_number = Participants.next_bib_number(race.id)
        token = generate_token()
        reg_opts = registration_opts(race)

        initial_status = if race.payment_required, do: :pending_payment, else: :registered

        changeset =
          %Participant{
            race_id: race.id,
            bib_number: bib_number,
            confirmation_token: token,
            status: initial_status
          }
          |> Participant.registration_changeset(attrs, reg_opts)

        email = field(changeset, :email)
        first_name = field(changeset, :first_name)
        last_name = field(changeset, :last_name)

        duplicate =
          if changeset.valid?,
            do: Participants.find_duplicate_registration(race.id, first_name, last_name, email)

        cond do
          is_nil(duplicate) ->
            insert_registration(race, changeset, email)

          duplicate.status == :pending_payment ->
            resume_pending_registration(duplicate, attrs, reg_opts)

          true ->
            {:error, :duplicate, duplicate}
        end
    end
  end

  # User started a paid registration, never paid, and is back submitting again.
  # Update the existing pending row in place — keep its bib number, confirmation
  # token, and user link — so the caller can hand them a fresh checkout session.
  defp resume_pending_registration(participant, attrs, reg_opts) do
    participant
    |> Participant.registration_changeset(attrs, reg_opts)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, :race_category)}
      {:error, _} = err -> err
    end
  end

  defp field(changeset, key) do
    Ecto.Changeset.get_change(changeset, key) || Ecto.Changeset.get_field(changeset, key)
  end

  defp insert_registration(race, changeset, email) do
    case Repo.insert(changeset) do
      {:ok, participant} ->
        user = find_or_create_user(email)

        if user do
          participant
          |> Ecto.Changeset.change(%{user_id: user.id})
          |> Repo.update!()
        end

        participant = Repo.preload(participant, :race_category)

        unless race.payment_required do
          RegistrationNotifier.deliver_confirmation(participant, race)
        end

        {:ok, participant}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for the registration form.
  """
  def change_registration(%Participant{} = participant, attrs \\ %{}, opts \\ []) do
    Participant.registration_changeset(participant, attrs, opts)
  end

  defp registration_opts(race) do
    race = Bibtime.Repo.preload(race, [:categories, :auto_categories])
    auto_cat_types = race.auto_categories |> Enum.map(& &1.type) |> Enum.uniq()

    [
      require_category: race.categories != [],
      require_gender: :gender in auto_cat_types,
      require_birth_date: :age_group in auto_cat_types
    ]
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
