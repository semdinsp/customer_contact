defmodule CustomerContact.CSVTest do
  use ExUnit.Case, async: true

  alias CustomerContact.CSV

  test "parses quoted fields with commas, doubled quotes and line breaks" do
    assert CSV.parse(~s|a,"b, c","say ""hi""","two\nlines"\r\nd,,e\n|) ==
             [["a", "b, c", ~s|say "hi"|, "two\nlines"], ["d", "", "e"]]
  end

  test "reads email and name columns by header, in any order and case, ignoring others" do
    csv = "﻿Phone,Name,E-mail\r\n555,Jane Doe, Jane@Example.com \r\n,,\r\n556,,lee@example.org\r\n"

    assert CSV.parse_people(csv) ==
             {:ok,
              [
                %{line: 2, email: "Jane@Example.com", name: "Jane Doe"},
                %{line: 4, email: "lee@example.org", name: nil}
              ]}
  end

  test "joins first and last name columns and accepts semicolon separators" do
    assert {:ok, [%{email: "a@example.com", name: "Ann Lee"}]} =
             CSV.parse_people("email;first_name;last name\na@example.com;Ann;Lee\n")
  end

  test "refuses files without an email column or that aren't UTF-8" do
    assert {:error, "The first row must be a header" <> _} = CSV.parse_people("name\nJane\n")
    assert {:error, "The file isn't UTF-8" <> _} = CSV.parse_people(<<"email\n", 0xFF, "@x.com\n">>)
  end
end
