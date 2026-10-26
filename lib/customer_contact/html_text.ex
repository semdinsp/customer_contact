defmodule CustomerContact.HTMLText do
  @moduledoc """
  Converts campaign HTML to a readable plain-text alternative. Not a full HTML
  parser: good enough for the text part of an email.
  """

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "mdash" => "—",
    "ndash" => "–",
    "rsquo" => "’",
    "lsquo" => "‘",
    "rdquo" => "”",
    "ldquo" => "“",
    "hellip" => "…",
    "copy" => "©",
    "bull" => "•",
    "rarr" => "→"
  }

  @anchor ~r/<a\b[^>]*\bhref\s*=\s*["']([^"']*)["'][^>]*>((?:(?!<a\b).)*?)<\/a\s*>/is

  def convert(nil), do: ""

  def convert(html) do
    html
    # Each lazy match stops at the next opening tag of its kind, so unclosed
    # comments, blocks or links can't make these quadratic.
    |> String.replace(~r/<!--(?:(?!<!--).)*?-->/s, "")
    |> String.replace(~r/<(head|style|script|title)\b[^>]*>(?:(?!<\1\b).)*?<\/\1\s*>/is, "")
    |> String.replace(@anchor, &link/1)
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<li\b[^>]*>/i, "\n- ")
    |> String.replace(~r/<\/(p|div|h[1-6]|tr|table|ul|ol|blockquote)\s*>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_entities()
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/ *\n */, "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp link(match) do
    [_, href, text] = Regex.run(@anchor, match)
    text = text |> String.replace(~r/<[^>]+>/, "") |> String.trim()
    href = decode_entities(href)

    cond do
      href == "" or String.starts_with?(href, "#") -> text
      text == "" or text == href -> href
      true -> "#{text} (#{href})"
    end
  end

  def decode_entities(text) do
    Regex.replace(~r/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/, text, fn whole, code ->
      case code do
        "#x" <> hex -> codepoint(Integer.parse(hex, 16), whole)
        "#" <> dec -> codepoint(Integer.parse(dec), whole)
        name -> Map.get(@entities, name, whole)
      end
    end)
  end

  defp codepoint({n, ""}, _whole) when n in 0..0x10FFFF, do: <<n::utf8>>
  defp codepoint(_, whole), do: whole
end
