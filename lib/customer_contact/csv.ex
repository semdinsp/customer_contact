defmodule CustomerContact.CSV do
  @moduledoc false
  # Just enough CSV for importing people on the Audience page: quoted fields
  # (with commas, doubled quotes and line breaks inside), CRLF or LF line
  # endings, a UTF-8 byte order mark, and comma or semicolon separators
  # (Excel uses semicolons in some locales).

  @doc """
  Parses a CSV file whose first row is a header with an email column and,
  optionally, a name column (or first name and last name columns).

  Returns `{:ok, rows}` where each row is `%{line: row number, email: e, name: n}`,
  skipping blank lines, or `{:error, message}`.
  """
  def parse_people(binary) when is_binary(binary) do
    binary = String.replace_prefix(binary, <<0xEF, 0xBB, 0xBF>>, "")

    if String.valid?(binary) do
      [header | rows] = parse(binary, separator(binary))
      columns = header |> Enum.map(&normalize_header/1) |> Enum.with_index() |> Map.new()

      case column(columns, ["email", "e-mail", "email address", "e-mail address"]) do
        nil ->
          {:error, "The first row must be a header with an email column."}

        email_at ->
          name_at =
            case column(columns, ["name", "full name"]) do
              nil ->
                Enum.reject(
                  [column(columns, ["first name", "firstname"]), column(columns, ["last name", "lastname", "surname"])],
                  &is_nil/1
                )

              i ->
                [i]
            end

          rows =
            for {fields, line} <- Enum.with_index(rows, 2), Enum.any?(fields, &(String.trim(&1) != "")) do
              name = name_at |> Enum.map_join(" ", &String.trim(Enum.at(fields, &1) || "")) |> String.trim()
              %{line: line, email: String.trim(Enum.at(fields, email_at) || ""), name: blank_to_nil(name)}
            end

          {:ok, rows}
      end
    else
      {:error, "The file isn't UTF-8 text. Save it as \"CSV UTF-8\" and try again."}
    end
  end

  defp column(columns, names), do: Enum.find_value(names, &Map.get(columns, &1))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp normalize_header(h), do: h |> String.trim() |> String.downcase() |> String.replace("_", " ")

  defp separator(binary) do
    first_line = binary |> String.split(["\r\n", "\n"], parts: 2) |> hd()
    if String.contains?(first_line, ";") and not String.contains?(first_line, ","), do: ?;, else: ?,
  end

  @doc "Parses CSV into a list of rows, each a list of field strings. Always returns at least one row."
  def parse(binary, sep \\ ?,), do: parse(binary, sep, "", [], [])

  # parse(rest, separator, current field, fields of current row reversed, rows reversed)
  defp parse(<<>>, _sep, field, fields, rows), do: Enum.reverse([Enum.reverse([field | fields]) | rows])
  defp parse(<<?", rest::binary>>, sep, "", fields, rows), do: quoted(rest, sep, "", fields, rows)
  defp parse(<<"\r\n", rest::binary>>, sep, field, fields, rows), do: new_row(rest, sep, field, fields, rows)
  defp parse(<<?\n, rest::binary>>, sep, field, fields, rows), do: new_row(rest, sep, field, fields, rows)

  defp parse(<<c, rest::binary>>, sep, field, fields, rows) when c == sep,
    do: parse(rest, sep, "", [field | fields], rows)

  defp parse(<<c, rest::binary>>, sep, field, fields, rows), do: parse(rest, sep, <<field::binary, c>>, fields, rows)

  defp new_row(<<>>, _sep, field, fields, rows), do: Enum.reverse([Enum.reverse([field | fields]) | rows])
  defp new_row(rest, sep, field, fields, rows), do: parse(rest, sep, "", [], [Enum.reverse([field | fields]) | rows])

  defp quoted(<<?", ?", rest::binary>>, sep, field, fields, rows),
    do: quoted(rest, sep, <<field::binary, ?">>, fields, rows)

  defp quoted(<<?", rest::binary>>, sep, field, fields, rows), do: parse(rest, sep, field, fields, rows)
  defp quoted(<<c, rest::binary>>, sep, field, fields, rows), do: quoted(rest, sep, <<field::binary, c>>, fields, rows)
  # An unclosed quote runs to the end of the file.
  defp quoted(<<>>, sep, field, fields, rows), do: parse(<<>>, sep, field, fields, rows)
end
