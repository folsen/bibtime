defmodule Bibtime.Repo.Migrations.CreateRaces do
  use Ecto.Migration

  def change do
    create table(:races) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :date, :date
      add :location, :string
      add :race_type, :string, null: false, default: "triathlon"
      add :status, :string, null: false, default: "draft"
      add :config, :map, default: %{}

      timestamps()
    end

    create unique_index(:races, [:slug])

    create table(:race_categories) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :distance_label, :string
      add :gender, :string, default: "any"
      add :min_age, :integer
      add :max_age, :integer
      add :sort_order, :integer, null: false, default: 0

      timestamps()
    end

    create index(:race_categories, [:race_id])

    create table(:splits) do
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :short_name, :string, null: false
      add :leg_type, :string, null: false
      add :distance_meters, :integer
      add :sort_order, :integer, null: false, default: 0

      timestamps()
    end

    create index(:splits, [:race_id])
  end
end
