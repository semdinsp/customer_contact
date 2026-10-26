defmodule CustomerContact.Contact do
  @moduledoc false
  # A person an admin added by hand on the Audience page, alongside the
  # people the host app supplies. Their recipient ref is "manual:<id>".
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cc_contacts" do
    field :email, :string
    field :name, :string
    field :added_by, :string
    field :consent_note, :string
    field :consent, :boolean, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:email, :name, :consent])
    |> update_change(:email, &CustomerContact.Audience.normalize_email/1)
    |> validate_required([:email])
    |> validate_change(:email, fn :email, email ->
      if CustomerContact.Audience.valid_email?(email), do: [], else: [email: "must be a valid email"]
    end)
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 120)
    |> validate_acceptance(:consent, message: "confirm they agreed to receive emails")
    |> unique_constraint(:email, message: "has already been added")
  end
end
