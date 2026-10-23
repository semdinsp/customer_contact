defmodule CustomerContact.Tracking do
  @moduledoc """
  Signed tracking URLs (open pixel, click redirect, unsubscribe) and the
  recording of those events.

  Tokens are signed with the host endpoint's `secret_key_base`, so they cannot
  be forged, and click tokens carry the destination URL, so the redirect
  endpoint cannot be used as an open redirect.
  """

  import Ecto.Query

  alias CustomerContact.{Audience, Delivery, Event}

  @open_salt "customer_contact open"
  @click_salt "customer_contact click"
  @unsubscribe_salt "customer_contact unsubscribe"

  ## URLs

  def open_url(delivery_id), do: CustomerContact.public_url("/o/" <> sign(@open_salt, delivery_id) <> ".gif")

  def click_url(delivery_id, url), do: CustomerContact.public_url("/c/" <> sign(@click_salt, {delivery_id, url}))

  def unsubscribe_url(delivery_id, email) do
    CustomerContact.public_url("/u/" <> sign(@unsubscribe_salt, {delivery_id, Audience.normalize_email(email)}))
  end

  ## Token verification

  def verify_open(token), do: verify(@open_salt, String.replace_suffix(token, ".gif", ""))

  def verify_click(token) do
    with {:ok, {delivery_id, url}} <- verify(@click_salt, token),
         true <- safe_redirect?(url) do
      {:ok, {delivery_id, url}}
    else
      _ -> :error
    end
  end

  def verify_unsubscribe(token) do
    case verify(@unsubscribe_salt, token) do
      {:ok, {delivery_id, email}} -> {:ok, {delivery_id, email}}
      _ -> :error
    end
  end

  defp sign(salt, data), do: Phoenix.Token.sign(CustomerContact.endpoint(), salt, data)

  defp verify(salt, token) do
    case Phoenix.Token.verify(CustomerContact.endpoint(), salt, token, max_age: :infinity) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> :error
    end
  end

  defp safe_redirect?(url) when is_binary(url) do
    match?(
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "",
      URI.parse(url)
    )
  end

  defp safe_redirect?(_), do: false

  ## Recording

  def record_open(delivery_id) do
    now = now()

    {count, _} =
      from(d in Delivery,
        where: d.id == ^delivery_id,
        update: [
          inc: [open_count: 1],
          set: [first_opened_at: coalesce(d.first_opened_at, ^now), updated_at: ^now]
        ]
      )
      |> repo().update_all([])

    if count == 1, do: insert_event(delivery_id, "open")
    :ok
  end

  @doc "Records a click. A click also counts as an open, since images may be blocked."
  def record_click(delivery_id, url) do
    now = now()

    {count, _} =
      from(d in Delivery,
        where: d.id == ^delivery_id,
        update: [
          inc: [click_count: 1],
          set: [
            first_clicked_at: coalesce(d.first_clicked_at, ^now),
            first_opened_at: coalesce(d.first_opened_at, ^now),
            updated_at: ^now
          ]
        ]
      )
      |> repo().update_all([])

    if count == 1, do: insert_event(delivery_id, "click", %{url: url})
    :ok
  end

  def record_unsubscribe(delivery_id, email) do
    {:ok, _} = Audience.suppress(email, "unsubscribe", "Unsubscribe link")

    if delivery_id do
      now = now()

      {count, _} =
        from(d in Delivery, where: d.id == ^delivery_id and is_nil(d.unsubscribed_at))
        |> repo().update_all(set: [unsubscribed_at: now, updated_at: now])

      if count == 1, do: insert_event(delivery_id, "unsubscribe")
    end

    :ok
  end

  @doc false
  def insert_event(delivery_id, type, attrs \\ %{}) do
    %Event{delivery_id: delivery_id, type: type, url: attrs[:url], detail: attrs[:detail]}
    |> repo().insert()
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp repo, do: CustomerContact.repo()
end
