defmodule Bibtime.Repo.Migrations.DropParticipantsEmail do
  use Ecto.Migration

  # Email is now stored only on the linked user. Historic CSV-imported
  # participants without a user_id stay user-less by design — they're a
  # read-only public record of past races, not accounts. Their email is
  # dropped along with the column.
  def up do
    alter table(:participants) do
      remove :email
    end
  end

  def down do
    alter table(:participants) do
      add :email, :string
    end

    # Best-effort restoration from linked users. Historic participants
    # without a user_id can't be restored — their email was lost in `up`.
    execute("""
    UPDATE participants
    SET email = (
      SELECT u.email FROM users u WHERE u.id = participants.user_id
    )
    WHERE user_id IS NOT NULL
    """)
  end
end
