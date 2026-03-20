defmodule Bibtime.Timing.SplitTime do
  use Ecto.Schema
  import Ecto.Changeset

  schema "split_times" do
    field :absolute_time, :utc_datetime_usec
    field :elapsed_ms, :integer
    field :source, Ecto.Enum, values: [:chip, :manual, :import, :adjustment], default: :manual
    field :raw_chip_data, :string

    belongs_to :participant, Bibtime.Participants.Participant
    belongs_to :split, Bibtime.Races.Split

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(split_time, attrs) do
    split_time
    |> cast(attrs, [
      :absolute_time,
      :elapsed_ms,
      :source,
      :raw_chip_data,
      :participant_id,
      :split_id
    ])
    |> validate_required([:elapsed_ms, :source, :participant_id, :split_id])
    |> unique_constraint([:participant_id, :split_id])
  end
end
