defmodule Bibtime.Repo.Migrations.CreateRaceAutoCategories do
  use Ecto.Migration

  def change do
    create table(:race_auto_categories) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :name, :string, null: false
      add :gender_value, :string
      add :min_age, :integer
      add :max_age, :integer
      add :sort_order, :integer, default: 0, null: false

      timestamps()
    end

    create index(:race_auto_categories, [:race_id])
  end
end
