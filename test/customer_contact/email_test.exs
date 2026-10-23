defmodule CustomerContact.EmailTest do
  use CustomerContact.DataCase, async: true

  alias CustomerContact.{Delivery, Email, Tracking}

  setup do
    campaign = campaign_fixture()
    delivery = Repo.insert!(%Delivery{campaign_id: campaign.id, email: "jo@example.com", name: "Jo <b>Doe</b>"})
    %{campaign: campaign, delivery: delivery}
  end

  test "merges fields with HTML escaping and builds headers", %{campaign: campaign, delivery: delivery} do
    email = Email.build(campaign, delivery)

    assert email.subject == "Hello Jo"
    assert email.html_body =~ "Hi Jo &lt;b&gt;Doe&lt;/b&gt;"
    refute email.html_body =~ "<b>Doe</b>"
    assert email.from == {"Test Org", "news@example.test"}
    assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    assert email.headers["List-Unsubscribe"] =~ "<https://example.test/cc/u/"
    assert email.headers["X-SES-CONFIGURATION-SET"] == "test-set"
    assert email.html_body =~ "1 Test St, Testville"
    assert email.text_body =~ "Hi Jo <b>Doe</b>"
  end

  test "rewrites links to signed click URLs that decode to the original", %{campaign: campaign, delivery: delivery} do
    email = Email.build(campaign, delivery)
    refute email.html_body =~ ~s(href="https://example.org)
    [token] = Regex.run(~r{https://example\.test/cc/c/([^"]+)}, email.html_body, capture: :all_but_first)
    assert {:ok, {id, "https://example.org/page?a=1&b=2"}} = Tracking.verify_click(token)
    assert id == delivery.id
  end

  test "adds an open pixel", %{campaign: campaign, delivery: delivery} do
    email = Email.build(campaign, delivery)
    [token] = Regex.run(~r{https://example\.test/cc/o/([^"]+)}, email.html_body, capture: :all_but_first)
    assert {:ok, id} = Tracking.verify_open(token)
    assert id == delivery.id
  end

  test "test deliveries get a [TEST] subject", %{campaign: campaign, delivery: delivery} do
    assert Email.build(campaign, %{delivery | test: true}).subject == "[TEST] Hello Jo"
  end

  test "strips scripts and keeps a full document intact with layout none", %{delivery: delivery} do
    campaign =
      campaign_fixture(%{
        layout: "none",
        html_body: "<html><body><h1>Big</h1><script>alert(1)</script></body></html>"
      })

    html = Email.build(campaign, %{delivery | campaign_id: campaign.id}).html_body
    refute html =~ "<script"
    assert html =~ ~r{Unsubscribe</a>.*</div><img[^>]+/cc/o/.*</body></html>}s
  end

  test "subject merge strips newlines from names", %{campaign: campaign, delivery: delivery} do
    assert Email.build(campaign, %{delivery | name: "Evil\r\nBcc: x@y"}).subject == "Hello Evil"
  end

  test "tampered click tokens are rejected" do
    assert Tracking.verify_click("nonsense") == :error
  end

  test "click tokens for non-http URLs are rejected" do
    token = Phoenix.Token.sign(CustomerContact.TestEndpoint, "customer_contact click", {"id", "javascript:alert(1)"})
    assert Tracking.verify_click(token) == :error
  end
end
