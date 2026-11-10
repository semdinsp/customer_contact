defmodule CustomerContact.Image do
  @moduledoc false
  # An image uploaded on the Images page and served publicly from
  # `{public_path}/i/:id/:filename` so campaigns can embed it. The bytes live
  # in `data`; list queries leave that column out.
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cc_images" do
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer
    field :sha256, :string
    field :data, :binary, load_in_query: false
    field :uploaded_by, :string

    timestamps(type: :utc_datetime)
  end
end
