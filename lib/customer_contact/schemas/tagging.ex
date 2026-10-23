defmodule CustomerContact.Tagging do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cc_taggings" do
    belongs_to :tag, CustomerContact.Tag
    field :recipient_ref, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
