defmodule CustomerContact.Sender do
  @moduledoc false
  # Delivers one already-claimed delivery (status "sending") and records the
  # outcome. Channels other than email (e.g. SMS) will dispatch from here.

  import Ecto.Query

  alias CustomerContact.{Delivery, Email, Log}

  def deliver(%Delivery{channel: "email"} = delivery, campaign) do
    result =
      try do
        delivery
        |> then(&Email.build(campaign, &1))
        |> CustomerContact.mailer().deliver()
      rescue
        e -> {:error, Exception.message(e)}
      end

    case result do
      {:ok, response} ->
        message_id = message_id(response)
        mark(delivery, status: "sent", sent_at: now(), provider_message_id: message_id, error: nil)
        Log.info("sent email", log_meta(delivery) ++ [ses_message_id: message_id])
        :ok

      {:error, reason} ->
        error = format_error(reason)
        Log.warning("mailer refused email", log_meta(delivery) ++ [error: error])
        {:error, error}
    end
  end

  def deliver(%Delivery{channel: channel}, _campaign), do: {:error, "unsupported channel #{channel}"}

  @doc false
  def mark(%Delivery{id: id}, fields) do
    from(d in Delivery, where: d.id == ^id)
    |> CustomerContact.repo().update_all(set: Keyword.put(fields, :updated_at, now()))
  end

  @doc false
  def log_meta(%Delivery{} = d),
    do: [campaign_id: d.campaign_id, delivery_id: d.id, to: Log.mask_email(d.email), test: d.test]

  defp message_id(%{id: id}) when is_binary(id), do: id
  defp message_id(%{"id" => id}) when is_binary(id), do: id
  defp message_id(_), do: nil

  defp format_error({_code, %{} = body}), do: inspect(body) |> String.slice(0, 500)
  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 500)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
