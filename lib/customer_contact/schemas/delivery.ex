defmodule CustomerContact.Delivery do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # queued -> sending -> sent -> delivered | bounced | complained
  # queued -> cancelled | failed
  @statuses ~w(queued sending sent delivered bounced complained failed cancelled)

  schema "cc_deliveries" do
    belongs_to :campaign, CustomerContact.Campaign
    field :test, :boolean, default: false
    field :channel, :string, default: "email"
    field :recipient_ref, :string
    field :email, :string
    field :name, :string
    field :status, :string, default: "queued"
    field :provider_message_id, :string
    field :error, :string
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :bounced_at, :utc_datetime
    field :complained_at, :utc_datetime
    field :first_opened_at, :utc_datetime
    field :open_count, :integer, default: 0
    field :first_clicked_at, :utc_datetime
    field :click_count, :integer, default: 0
    field :unsubscribed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
end
