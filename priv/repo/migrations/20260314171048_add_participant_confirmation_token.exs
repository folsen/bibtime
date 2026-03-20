defmodule Bibtime.Repo.Migrations.AddParticipantConfirmationToken do
  use Ecto.Migration

  def change do
    alter table(:participants) do
      add :confirmation_token, :string
    end

    create unique_index(:participants, [:confirmation_token])
  end
end
