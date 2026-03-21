defmodule Bibtime.Races.RaceAutoCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "race_auto_categories" do
    field :type, Ecto.Enum, values: [:gender, :age_group]
    field :name, :string
    field :gender_value, Ecto.Enum, values: [:male, :female, :other]
    field :min_age, :integer
    field :max_age, :integer
    field :sort_order, :integer, default: 0

    belongs_to :race, Bibtime.Races.Race

    timestamps()
  end

  @doc false
  def changeset(auto_category, attrs) do
    auto_category
    |> cast(attrs, [:type, :name, :gender_value, :min_age, :max_age, :sort_order, :race_id])
    |> validate_required([:type, :name, :race_id])
    |> validate_gender_type()
    |> validate_age_group_type()
  end

  defp validate_gender_type(changeset) do
    if get_field(changeset, :type) == :gender do
      validate_required(changeset, [:gender_value])
    else
      changeset
    end
  end

  defp validate_age_group_type(changeset) do
    if get_field(changeset, :type) == :age_group do
      changeset
      |> validate_number(:min_age, greater_than_or_equal_to: 0)
      |> validate_number(:max_age, greater_than: 0)
    else
      changeset
    end
  end
end
