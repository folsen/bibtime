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

  "Full" counts registered participants plus pending-payment participants
  whose hold has not expired — see `Participants.count_slots_taken/1`.
  """
  def registration_full?(%{participant_limit: nil}), do: false

  def registration_full?(%{participant_limit: limit, id: race_id}) do
    Participants.count_slots_taken(race_id) >= limit
  end

  @doc """
  Hold TTL for a pending-payment participant. Slightly longer than the
  Stripe checkout session's own expiry so a successful payment that lands
  close to the session deadline still finds a valid hold on our side.
  """
  @hold_ttl_seconds 35 * 60
  def hold_ttl_seconds, do: @hold_ttl_seconds

  @doc """
  Registers a participant for a race.

  For free races the participant is immediately `:registered` with a fresh
  bib number. For paid races the participant is inserted as
  `:pending_payment` with a hold on a race slot — no bib is assigned until
  payment completes, and the hold expires after `hold_ttl_seconds/0`.

  Also creates a user account if one doesn't exist for the participant's
  email and sends them login instructions.

  Returns `{:ok, participant}`, `{:error, changeset}`, `{:error, :duplicate, existing}`
  for a non-resumable duplicate, or `{:error, :race_full}` when a lapsed
  hold can't be refreshed because the race filled in the meantime.
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
        token = generate_token()
        reg_opts = registration_opts(race)

        {status, bib_number, hold_expires_at} = initial_slot_attrs(race)

        changeset =
          %Participant{
            race_id: race.id,
            bib_number: bib_number,
            hold_expires_at: hold_expires_at,
            confirmation_token: token,
            status: status
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
            resume_pending_registration(duplicate, attrs, reg_opts, race)

          true ->
            {:error, :duplicate, duplicate}
        end
    end
  end

  defp initial_slot_attrs(%{payment_required: true}),
    do: {:pending_payment, nil, fresh_hold_expiry()}

  defp initial_slot_attrs(_race),
    do: {:registered, nil, nil}

  defp fresh_hold_expiry do
    DateTime.utc_now()
    |> DateTime.add(@hold_ttl_seconds, :second)
    |> DateTime.truncate(:second)
  end

  # User started a paid registration, never paid, and is back submitting again.
  # Refresh their hold and keep the existing row — bib stays nil, confirmation
  # token + user link preserved — so the caller can hand them a fresh checkout
  # session. If their old hold had lapsed and the race has since filled, we
  # refuse the refresh rather than quietly letting them pay into a full race.
  defp resume_pending_registration(participant, attrs, reg_opts, race) do
    if expired_hold?(participant) and registration_full?(race) do
      {:error, :race_full}
    else
      participant
      |> Participant.registration_changeset(attrs, reg_opts)
      |> Ecto.Changeset.put_change(:hold_expires_at, fresh_hold_expiry())
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, Repo.preload(updated, :race_category)}
        {:error, _} = err -> err
      end
    end
  end

  defp expired_hold?(%Participant{hold_expires_at: nil}), do: true

  defp expired_hold?(%Participant{hold_expires_at: ts}) do
    DateTime.compare(ts, DateTime.utc_now()) == :lt
  end

  defp field(changeset, key) do
    Ecto.Changeset.get_change(changeset, key) || Ecto.Changeset.get_field(changeset, key)
  end

  defp insert_registration(race, changeset, email) do
    case Repo.insert(changeset) do
      {:ok, participant} ->
        # For paid races, bib assignment happens at payment. For free races,
        # pick a bib now so the confirmation email can render it.
        participant =
          if race.payment_required do
            participant
          else
            bib = Participants.next_bib_number(participant.race_id)

            participant
            |> Ecto.Changeset.change(%{bib_number: bib})
            |> Repo.update!()
          end

        {user, user_was_new?} = find_or_create_user(email)

        if user do
          participant
          |> Ecto.Changeset.change(%{user_id: user.id})
          |> Repo.update!()
        end

        if user_was_new?, do: Accounts.deliver_login_instructions(user)

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

  defp find_or_create_user(nil), do: {nil, false}

  defp find_or_create_user(email) do
    case Accounts.get_user_by_email(email) do
      %{} = user ->
        {user, false}

      nil ->
        case Accounts.register_user(%{email: email}) do
          {:ok, user} -> {user, true}
          {:error, _} -> {nil, false}
        end
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
