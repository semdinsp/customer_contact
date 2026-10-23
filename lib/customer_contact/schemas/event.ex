defmodule CustomerContact.Event do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cc_events" do
    belongs_to :delivery, CustomerContact.Delivery
    field :type, :string
    field :url, :string
    field :detail, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
