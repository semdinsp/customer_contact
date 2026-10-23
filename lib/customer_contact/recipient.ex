defmodule CustomerContact.Recipient do
  @moduledoc """
  A person the host app can contact.

  `ref` is the host's stable identifier for the person (e.g. a member id) as a
  string. It is used by the built-in tags and recorded on each delivery.
  """

  @enforce_keys [:ref, :email]
  defstruct [:ref, :email, :name, :phone]

  @type t :: %__MODULE__{
          ref: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          phone: String.t() | nil
        }
end
