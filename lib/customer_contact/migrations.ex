defmodule CustomerContact.Migrations do
  @moduledoc """
  Creates CustomerContact's tables. Call from a migration in the host app:

      defmodule MyApp.Repo.Migrations.AddCustomerContact do
        use Ecto.Migration

        def up, do: CustomerContact.Migrations.up(version: 1)
        def down, do: CustomerContact.Migrations.down(version: 1)
      end

  Later library versions add `version: 2` and so on; add a new host migration
  that calls `up(version: 2)` when upgrading.
  """

  use Ecto.Migration

  @latest 1

  def latest_version, do: @latest

  def up(opts \\ []) do
    for v <- 1..Keyword.get(opts, :version, @latest), do: change(v, :up)
  end

  def down(opts \\ []) do
    for v <- Keyword.get(opts, :version, @latest)..1//-1, do: change(v, :down)
  end

  defp change(1, :up) do
    create table(:cc_campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :channel, :string, null: false, default: "email"
      add :subject, :string
      add :preheader, :string
      add :html_body, :text
      add :layout, :string, null: false, default: "branded"
      add :segment_ids, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "draft"
      add :created_by, :string
      add :tested_hash, :string
      add :tested_at, :utc_datetime
      add :tested_by, :string
      add :approved_hash, :string
      add :approved_count, :integer
      add :approved_at, :utc_datetime
      add :approved_by, :string
      add :send_started_at, :utc_datetime
      add :send_completed_at, :utc_datetime
      add :sent_by, :string
      timestamps(type: :utc_datetime)
    end

    create index(:cc_campaigns, [:inserted_at])

    create table(:cc_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :campaign_id, references(:cc_campaigns, type: :binary_id, on_delete: :delete_all), null: false
      add :test, :boolean, null: false, default: false
      add :channel, :string, null: false, default: "email"
      add :recipient_ref, :string
      add :email, :string, null: false
      add :name, :string
      add :status, :string, null: false, default: "queued"
      add :provider_message_id, :string
      add :error, :text
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :bounced_at, :utc_datetime
      add :complained_at, :utc_datetime
      add :first_opened_at, :utc_datetime
      add :open_count, :integer, null: false, default: 0
      add :first_clicked_at, :utc_datetime
      add :click_count, :integer, null: false, default: 0
      add :unsubscribed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:cc_deliveries, [:campaign_id, :status])
    create index(:cc_deliveries, [:provider_message_id])

    create unique_index(:cc_deliveries, [:campaign_id, :email],
             where: "test = false",
             name: :cc_deliveries_campaign_email_index
           )

    create table(:cc_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :delivery_id, references(:cc_deliveries, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :url, :text
      add :detail, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:cc_events, [:delivery_id])

    create table(:cc_suppressions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :reason, :string, null: false
      add :note, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:cc_suppressions, [:email])

    create table(:cc_test_recipients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:cc_test_recipients, [:email])

    create table(:cc_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:cc_tags, [:name])

    create table(:cc_taggings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tag_id, references(:cc_tags, type: :binary_id, on_delete: :delete_all), null: false
      add :recipient_ref, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:cc_taggings, [:tag_id, :recipient_ref])
  end

  defp change(1, :down) do
    drop table(:cc_taggings)
    drop table(:cc_tags)
    drop table(:cc_test_recipients)
    drop table(:cc_suppressions)
    drop table(:cc_events)
    drop table(:cc_deliveries)
    drop table(:cc_campaigns)
  end
end
