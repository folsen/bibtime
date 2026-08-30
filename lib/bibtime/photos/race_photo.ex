defmodule Bibtime.Photos.RacePhoto do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:approved, :pending, :rejected]

  schema "race_photos" do
    field :file_path, :string
    field :original_filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :bib_numbers, {:array, :string}, default: []
    field :caption, :string
    field :taken_at, :utc_datetime
    field :sort_order, :integer, default: 0

    field :status, Ecto.Enum, values: @statuses, default: :approved
    field :reviewed_at, :utc_datetime
    field :rejection_reason, :string

    belongs_to :race, Bibtime.Races.Race
    belongs_to :split, Bibtime.Races.Split
    belongs_to :uploaded_by, Bibtime.Accounts.User, foreign_key: :uploaded_by_user_id
    belongs_to :reviewed_by, Bibtime.Accounts.User, foreign_key: :reviewed_by_user_id

    timestamps()
  end

  def statuses, do: @statuses

  @doc """
  Trusted changeset used by organizer/admin flows. Casts everything, including
  `status` — never drive this from a participant-supplied form.
  """
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
      :split_id,
      :status,
      :uploaded_by_user_id
    ])
    |> validate_required([:file_path, :race_id])
    |> validate_bib_numbers()
    |> validate_caption()
  end

  @doc """
  Changeset for a participant submission. The uploader may only influence the
  caption and bib tags; everything else — including `status` — is set by the
  server, so a crafted form can't self-approve.
  """
  def submission_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:caption, :bib_numbers])
    |> put_server_fields(attrs)
    |> validate_required([:file_path, :race_id, :uploaded_by_user_id])
    |> validate_bib_numbers()
    |> validate_caption()
  end

  def tag_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:bib_numbers, :caption, :split_id])
    |> validate_bib_numbers()
    |> validate_caption()
  end

  @doc """
  Changeset for an admin approving or rejecting a submission.
  """
  def review_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:status, :reviewed_by_user_id, :reviewed_at, :rejection_reason])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:rejection_reason, max: 500)
  end

  @server_fields [
    :race_id,
    :file_path,
    :original_filename,
    :content_type,
    :file_size,
    :uploaded_by_user_id
  ]

  defp put_server_fields(changeset, attrs) do
    changeset = put_change(changeset, :status, :pending)

    Enum.reduce(@server_fields, changeset, fn field, acc ->
      case fetch_attr(attrs, field) do
        nil -> acc
        value -> put_change(acc, field, value)
      end
    end)
  end

  defp fetch_attr(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp validate_caption(changeset) do
    validate_length(changeset, :caption, max: 300)
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
