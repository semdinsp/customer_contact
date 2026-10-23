defmodule CustomerContact.Email do
  @moduledoc """
  Builds the Swoosh email for one delivery of a campaign.

  Merge fields usable in the subject and HTML: `{{name}}`, `{{first_name}}`,
  `{{email}}` and `{{unsubscribe_url}}`. Values are HTML-escaped in the body.
  """

  import Swoosh.Email

  alias CustomerContact.{Campaign, Delivery, HTMLText, Layout, Tracking}

  @merge ~r/\{\{\s*([a-z_]+)\s*\}\}/

  @doc """
  Options:

    * `:track` - rewrite links and add the open pixel (default `true`)
  """
  def build(%Campaign{} = campaign, %Delivery{} = delivery, opts \\ []) do
    brand = CustomerContact.brand()
    unsubscribe_url = Tracking.unsubscribe_url(delivery.id, delivery.email)
    track? = Keyword.get(opts, :track, true)
    html = render_html(campaign, delivery, brand, unsubscribe_url, track?)

    subject =
      if delivery.test,
        do: "[TEST] " <> merge_text(campaign.subject, delivery),
        else: merge_text(campaign.subject, delivery)

    new()
    |> to(if(delivery.name in [nil, ""], do: delivery.email, else: {single_line(delivery.name), delivery.email}))
    |> from(brand.from)
    |> maybe_reply_to(brand[:reply_to])
    |> subject(subject)
    |> html_body(html)
    |> text_body(HTMLText.convert(html))
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> maybe_configuration_set(CustomerContact.ses_configuration_set())
  end

  @doc "HTML for the admin preview: no tracking, sample merge values."
  def preview_html(%Campaign{} = campaign) do
    sample = %Delivery{id: nil, email: "jane@example.com", name: "Jane Sample"}
    render_html(campaign, sample, CustomerContact.brand(), "#unsubscribe-preview", false)
  end

  defp render_html(campaign, delivery, brand, unsubscribe_url, track?) do
    body =
      (campaign.html_body || "")
      |> strip_scripts()
      |> then(&if(track?, do: track_links(&1, delivery.id), else: &1))
      |> merge_html(delivery, unsubscribe_url)

    pixel_url = if track?, do: Tracking.open_url(delivery.id)

    Layout.render(body, campaign.layout, campaign.preheader, brand, %{
      unsubscribe_url: unsubscribe_url,
      pixel_url: pixel_url
    })
  end

  @doc false
  def track_links(html, delivery_id) do
    Regex.replace(~r/(<a\b[^>]*?\bhref\s*=\s*)(["'])(https?:\/\/[^"']+)\2/i, html, fn _, prefix, quote, url ->
      prefix <> quote <> Tracking.click_url(delivery_id, HTMLText.decode_entities(url)) <> quote
    end)
  end

  defp strip_scripts(html), do: String.replace(html, ~r/<script\b[^>]*>.*?<\/script\s*>/is, "")

  defp merge_html(html, delivery, unsubscribe_url) do
    Regex.replace(@merge, html, fn whole, field ->
      case field_value(field, delivery, unsubscribe_url) do
        nil -> whole
        value -> value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      end
    end)
  end

  defp merge_text(nil, _delivery), do: ""

  defp merge_text(text, delivery) do
    Regex.replace(@merge, text, fn whole, field ->
      case field_value(field, delivery, nil) do
        nil -> whole
        value -> single_line(value)
      end
    end)
  end

  defp field_value("name", d, _), do: d.name || ""
  defp field_value("first_name", d, _), do: (d.name || "") |> String.split(~r/\s+/, trim: true) |> List.first("")
  defp field_value("email", d, _), do: d.email
  defp field_value("unsubscribe_url", _d, url), do: url
  defp field_value(_, _, _), do: nil

  defp single_line(text), do: String.replace(text, ~r/[\r\n]+/, " ")

  defp maybe_reply_to(email, nil), do: email
  defp maybe_reply_to(email, reply_to), do: reply_to(email, reply_to)

  defp maybe_configuration_set(email, nil), do: email
  defp maybe_configuration_set(email, set), do: header(email, "X-SES-CONFIGURATION-SET", set)
end
