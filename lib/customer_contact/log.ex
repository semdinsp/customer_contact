defmodule CustomerContact.Log do
  @moduledoc """
  Log lines for the campaign workflow, sending and email events.

  Every line starts with `[CustomerContact]` and ends with `key=value` pairs
  (`campaign_id`, `delivery_id`, `ses_message_id`, ...), which are also set as
  Logger metadata along with `customer_contact: true`. Search the app's logs
  for a campaign or delivery id to follow one email from send to bounce.

  Recipient addresses are masked (`a***@example.com`); the full address is on
  the campaign report.

  Successful sends and deliveries log at `:info`, one line per email. To
  quieten them, raise this module's level in the host app:

      Logger.put_module_level(CustomerContact.Log, :warning)
  """

  require Logger

  def info(message, meta \\ []), do: Logger.info(fn -> line(message, meta) end, metadata(meta))
  def warning(message, meta \\ []), do: Logger.warning(fn -> line(message, meta) end, metadata(meta))
  def error(message, meta \\ []), do: Logger.error(fn -> line(message, meta) end, metadata(meta))

  @doc "Masks the local part of an address: `alice@example.com` -> `a***@example.com`."
  def mask_email(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] -> String.slice(local, 0, 1) <> "***@" <> domain
      _ -> "***"
    end
  end

  def mask_email(_), do: nil

  defp line(message, meta) do
    pairs = for {key, value} <- meta, not is_nil(value), do: "#{key}=#{format(value)}"
    Enum.join(["[CustomerContact] " <> message | pairs], " ")
  end

  defp format(value) when is_binary(value), do: if(String.contains?(value, " "), do: inspect(value), else: value)
  defp format(value), do: inspect(value)

  defp metadata(meta), do: [{:customer_contact, true} | Keyword.reject(meta, fn {_, v} -> is_nil(v) end)]
end
