defmodule Bibtime.Repo.Migrations.AddPaymentIntegration do
  use Ecto.Migration

  def change do
    # Add payment fields to races
    alter table(:races) do
      add :payment_required, :boolean, default: false, null: false
      add :entry_fee_cents, :integer
      add :currency, :string, default: "SEK"
      add :early_bird_fee_cents, :integer
      add :early_bird_deadline, :date
    end

    # Create payments table
    create table(:payments) do
      add :participant_id, references(:participants, on_delete: :delete_all), null: false
      add :race_id, references(:races, on_delete: :delete_all), null: false
      add :stripe_checkout_session_id, :string
      add :stripe_payment_intent_id, :string
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false
      add :status, :string, default: "pending", null: false
      add :paid_at, :utc_datetime
      add :refunded_at, :utc_datetime

      timestamps()
    end

    create index(:payments, [:participant_id])
    create index(:payments, [:race_id])
    create unique_index(:payments, [:stripe_checkout_session_id])
    create index(:payments, [:stripe_payment_intent_id])
  end
end
