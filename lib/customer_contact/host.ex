defmodule CustomerContact.Host do
  @moduledoc """
  Behaviour the host app implements to tell CustomerContact who it can contact
  and how its emails should look.

  `list_segments/0` and `recipients_for_segments/1` are optional. When the host
  implements them (e.g. it already has its own tags), campaigns target those
  segments. Otherwise CustomerContact's built-in tags are used, managed on the
  Audience page.

  Segment ids are strings. `"all"` is reserved and always means every recipient
  returned by `list_recipients/0`.

  Only return people who may be contacted: the host should leave out anyone it
  has blocked. CustomerContact separately skips its own suppression list
  (unsubscribes, hard bounces and complaints).
  """

  alias CustomerContact.Recipient

  @typedoc """
  Brand used by the email layout. Keys:

    * `:name` (required) - organisation name, shown in header and footer
    * `:from` (required) - `{name, address}`; address must be verified in SES
    * `:postal_address` (required for bulk mail under CAN-SPAM/CASL)
    * `:reply_to`, `:logo_url`, `:website_url`
    * `:primary_color`, `:accent_color`, `:background_color` - hex strings
  """
  @type brand :: %{
          required(:name) => String.t(),
          required(:from) => {String.t(), String.t()},
          optional(atom()) => term()
        }

  @type segment :: %{id: String.t(), name: String.t(), count: non_neg_integer()}

  @callback brand() :: brand()
  @callback list_recipients() :: [Recipient.t()]
  @callback list_segments() :: [segment()]
  @callback recipients_for_segments([String.t()]) :: [Recipient.t()]

  @optional_callbacks list_segments: 0, recipients_for_segments: 1
end
