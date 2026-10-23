defmodule CustomerContact.Tag do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cc_tags" do
    field :name, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :description])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
    |> validate_length(:description, max: 250)
    |> unique_constraint(:name)
  end
end
