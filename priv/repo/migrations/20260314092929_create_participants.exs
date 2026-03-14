defmodule Bibtime.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:participants) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :race_category_id, references(:race_categories, on_delete: :nilify_all)
      add :bib_number, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :email, :string
      add :birth_date, :date
      add :gender, :string
      add :club, :string
      add :chip_id, :string
      add :status, :string, null: false, default: "registered"
      add :registration_data, :map, default: %{}

      timestamps()
    end

    create unique_index(:participants, [:race_id, :bib_number])
    create index(:participants, [:race_id])
    create index(:participants, [:race_category_id])
    create index(:participants, [:race_id, :chip_id])
  end
end
