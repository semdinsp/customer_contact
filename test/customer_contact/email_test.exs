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

  test "uses the fallback after | when a merge value is blank", %{campaign: campaign} do
    campaign = %{
      campaign
      | subject: "Hello {{ first_name | friend }}",
        html_body: "<p>Hi {{first_name|there}}, {{name}}</p>"
    }

    delivery = Repo.insert!(%Delivery{campaign_id: campaign.id, email: "anon@example.com", name: nil})
    email = Email.build(campaign, delivery)

    assert email.subject == "Hello friend"
    assert email.html_body =~ "<p>Hi there, </p>"

    named = Repo.insert!(%Delivery{campaign_id: campaign.id, email: "jo.doe@example.com", name: "Jo Doe"})
    assert Email.build(campaign, named).html_body =~ "<p>Hi Jo, Jo Doe</p>"
  end

  test "escapes merge fallbacks in HTML", %{campaign: campaign} do
    campaign = %{campaign | html_body: "<p>Hi {{first_name|<i>you</i>}}</p>"}
    delivery = Repo.insert!(%Delivery{campaign_id: campaign.id, email: "anon@example.com", name: ""})
    assert Email.build(campaign, delivery).html_body =~ "Hi &lt;i&gt;you&lt;/i&gt;"
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

  test "stripping scripts stays fast on unclosed script tags", %{campaign: campaign} do
    campaign = %{campaign | html_body: String.duplicate("<script>x ", 20_000)}
    {micros, _} = :timer.tc(fn -> CustomerContact.Email.preview_html(campaign) end)
    assert micros < 2_000_000, "took #{div(micros, 1000)} ms"
  end

  test "mask_emails masks every address in an error message" do
    text = ~s(Email address is not verified: Jane <jane.doe@example.com>, "bob@x.org")

    assert CustomerContact.Log.mask_emails(text) ==
             ~s(Email address is not verified: Jane <j***@example.com>, "b***@x.org")
  end
end
