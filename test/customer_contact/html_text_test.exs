defmodule CustomerContact.HTMLTextTest do
  use ExUnit.Case, async: true

  alias CustomerContact.HTMLText

  test "converts html to readable text" do
    html = """
    <html><head><style>p{color:red}</style></head><body>
    <h1>Title</h1><p>One &amp; two<br>three</p>
    <ul><li>a</li><li>b</li></ul>
    <a href="https://x.test/?a=1&amp;b=2">Link</a> &#8212; &copy;
    </body></html>
    """

    text = HTMLText.convert(html)
    assert text =~ "Title\n\nOne & two\nthree"
    assert text =~ "- a\n- b"
    assert text =~ "Link (https://x.test/?a=1&b=2) — ©"
    refute text =~ "color:red"
  end
end
