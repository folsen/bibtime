defmodule Bibtime.Photos.RacePhoto do
  use Ecto.Schema
  import Ecto.Changeset

  schema "race_photos" do
    field :file_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :bib_numbers, {:array, :string}, default: []
    field :caption, :string
    field :taken_at, :utc_datetime
    field :sort_order, :integer, default: 0

    belongs_to :race, Bibtime.Races.Race
    belongs_to :split, Bibtime.Races.Split

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [
      :file_path,
      :original_filename,
      :content_type,
      :file_size,
      :bib_numbers,
      :caption,
      :taken_at,
      :sort_order,
      :race_id,
      :split_id
    ])
    |> validate_required([:file_path, :race_id])
    |> validate_bib_numbers()
  end

  def tag_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:bib_numbers, :caption, :split_id])
    |> validate_bib_numbers()
  end

  defp validate_bib_numbers(changeset) do
    case get_change(changeset, :bib_numbers) do
      nil ->
        changeset

      bibs when is_list(bibs) ->
        if Enum.all?(bibs, &is_binary/1) do
          changeset
        else
          add_error(changeset, :bib_numbers, "must be a list of strings")
        end

      _ ->
        add_error(changeset, :bib_numbers, "must be a list of strings")
    end
  end
end
