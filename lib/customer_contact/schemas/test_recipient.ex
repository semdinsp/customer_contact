defmodule CustomerContact.TestRecipient do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "cc_test_recipients" do
    field :email, :string
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(test_recipient, attrs) do
    test_recipient
    |> cast(attrs, [:email, :name])
    |> update_change(:email, &CustomerContact.Audience.normalize_email/1)
    |> validate_required([:email])
    |> validate_change(:email, fn :email, email ->
      if CustomerContact.Audience.valid_email?(email), do: [], else: [email: "must be a valid email"]
    end)
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 120)
    |> unique_constraint(:email)
  end
end
