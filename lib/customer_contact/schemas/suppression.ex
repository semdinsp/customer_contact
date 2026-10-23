defmodule CustomerContact.Suppression do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @reasons ~w(unsubscribe bounce complaint manual)

  schema "cc_suppressions" do
    field :email, :string
    field :reason, :string
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(suppression, attrs) do
    suppression
    |> cast(attrs, [:email, :reason, :note])
    |> update_change(:email, &CustomerContact.Audience.normalize_email/1)
    |> validate_required([:email, :reason])
    |> validate_inclusion(:reason, @reasons)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must be a valid email")
    |> validate_length(:note, max: 250)
    |> unique_constraint(:email)
  end
end
