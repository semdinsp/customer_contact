defmodule CustomerContact.Layout do
  @moduledoc """
  Wraps campaign HTML in the host's branded email layout, or, for campaigns
  that paste a complete HTML document, injects the required footer into it.

  Brand values are escaped; the campaign HTML is inserted as written, since it
  is authored by an admin.
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  @doc """
  `footer` is a map with `:unsubscribe_url` and optional `:pixel_url`.
  """
  def render(content_html, layout, preheader, brand, footer)

  def render(content_html, "none", preheader, brand, footer) do
    insert = footer_html(brand, footer) <> pixel_html(footer)
    content_html = preheader_html(preheader) <> (content_html || "")

    if Regex.match?(~r/<\/body\s*>/i, content_html) do
      Regex.replace(~r/<\/body\s*>/i, content_html, insert <> "</body>", global: false)
    else
      content_html <> insert
    end
  end

  def render(content_html, "branded", preheader, brand, footer) do
    primary = color(brand[:primary_color], "#1f2937")
    bg = color(brand[:background_color], "#f3f4f6")
    name = esc(brand[:name])

    header =
      case brand[:logo_url] do
        url when is_binary(url) and url != "" ->
          ~s(<img src="#{esc(url)}" alt="#{name}" width="120" style="display:block;margin:0 auto 12px auto;border:0;max-width:120px;height:auto;" />) <>
            ~s(<div style="color:#ffffff;font-size:20px;font-weight:bold;">#{name}</div>)

        _ ->
          ~s(<div style="color:#ffffff;font-size:20px;font-weight:bold;">#{name}</div>)
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>#{name}</title>
    </head>
    <body style="margin:0;padding:0;background-color:#{bg};">
    #{preheader_html(preheader)}
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#{bg};padding:24px 12px;">
    <tr><td align="center">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#ffffff;border-radius:10px;overflow:hidden;">
    <tr><td style="background-color:#{primary};padding:24px 32px;text-align:center;font-family:Helvetica,Arial,sans-serif;">#{header}</td></tr>
    <tr><td style="padding:32px;font-family:Helvetica,Arial,sans-serif;font-size:16px;line-height:1.6;color:#374151;">
    #{content_html}
    </td></tr>
    <tr><td style="background-color:#{bg};padding:8px 32px 20px 32px;">#{footer_html(brand, footer)}</td></tr>
    </table>
    </td></tr>
    </table>
    #{pixel_html(footer)}
    </body>
    </html>
    """
  end

  defp preheader_html(nil), do: ""
  defp preheader_html(""), do: ""

  defp preheader_html(text) do
    ~s(<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">#{esc(text)}</div>)
  end

  defp footer_html(brand, footer) do
    accent = color(brand[:accent_color], "#2563eb")

    lines =
      [
        esc(brand[:name]),
        brand[:postal_address] && esc(brand[:postal_address]),
        brand[:website_url] &&
          ~s(<a href="#{esc(brand[:website_url])}" style="color:#{accent};">#{esc(brand[:website_url])}</a>),
        ~s(You are receiving this email because you are on the #{esc(brand[:name])} mailing list.),
        ~s(<a href="#{esc(footer.unsubscribe_url)}" style="color:#{accent};">Unsubscribe</a>)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("<br />")

    ~s(<div style="text-align:center;font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#6b7280;padding-top:16px;">#{lines}</div>)
  end

  defp pixel_html(%{pixel_url: url}) when is_binary(url) do
    ~s(<img src="#{esc(url)}" width="1" height="1" alt="" style="display:block;width:1px;height:1px;border:0;" />)
  end

  defp pixel_html(_), do: ""

  defp color(value, default) do
    if is_binary(value) and Regex.match?(~r/\A#[0-9a-fA-F]{3,8}\z/, value), do: value, else: default
  end

  defp esc(nil), do: ""
  defp esc(value), do: value |> to_string() |> html_escape() |> safe_to_string()
end
