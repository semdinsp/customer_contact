defmodule CustomerContact.Web.AdminLiveTest do
  use CustomerContact.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias CustomerContact.Campaigns

  @endpoint CustomerContact.TestEndpoint

  defp admin_conn, do: build_conn() |> Plug.Test.init_test_session(%{"admin" => true})

  test "non-admins are turned away by the host on_mount" do
    assert {:error, {:redirect, %{to: "/login"}}} =
             live(Plug.Test.init_test_session(build_conn(), %{}), "/admin/contact")
  end

  test "the header's home icon links to the router's home_path" do
    {:ok, view, _html} = live(admin_conn(), "/admin/contact")
    assert has_element?(view, ~s|#cc-home[href="/admin"]|)
  end

  test "a refused click shows its message at the top and pinned to the screen, and is logged" do
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)
    test_recipient_fixture()
    {:ok, campaign} = Campaigns.create_campaign(%{name: "No subject", html_body: "<p>Hi</p>"}, "admin")
    {:ok, view, _html} = live(admin_conn(), "/admin/contact/campaigns/" <> campaign.id)

    log = ExUnit.CaptureLog.capture_log([level: :info], fn -> view |> element("#send-test") |> render_click() end)

    assert has_element?(view, "#cc-flash-error", "Add a subject first.")
    assert has_element?(view, "#cc-toast-error", "Add a subject first.")
    assert log =~ "[CustomerContact] test send refused campaign_id=#{campaign.id}"
    assert log =~ "reason=missing_subject"

    view |> element("#cc-toast-error button") |> render_click()
    refute has_element?(view, "#cc-toast-error")
    refute has_element?(view, "#cc-flash-error")
  end

  test "create, test, approve and send a campaign" do
    test_recipient_fixture()
    {:ok, view, _html} = live(admin_conn(), "/admin/contact/campaigns/new")

    {:error, {:live_redirect, %{to: "/admin/contact/campaigns/" <> id}}} =
      view
      |> form("#campaign-form",
        campaign: %{name: "Fall", subject: "Hi {{first_name}}", html_body: "<p>Hello</p>", segment_ids: ["all"]}
      )
      |> render_submit()

    {:ok, view, html} = live(admin_conn(), "/admin/contact/campaigns/" <> id)
    assert html =~ "sandbox=\"\""
    assert has_element?(view, "#deliverable-count", "2")

    view |> element("#send-test") |> render_click()
    assert_email_sent(subject: "[TEST] Hi Tester")
    assert has_element?(view, "#tested-status")

    assert view |> form("#approve-form", count: "5") |> render_submit() =~ "does not match"
    view |> form("#approve-form", count: "2") |> render_submit()
    assert has_element?(view, "#approved-status")

    {:error, {:live_redirect, %{to: to}}} = view |> element("#send-campaign") |> render_click()
    assert to == "/admin/contact/campaigns/#{id}/report"
    assert Campaigns.get_campaign!(id).status == "sending"
    assert_enqueued(worker: CustomerContact.Workers.Dispatch)

    {:ok, _view, html} = live(admin_conn(), to)
    assert html =~ "Cancel sending"
  end

  test "audience page manages test recipients and built-in tags" do
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")
    view |> form("#test-recipient-form", test_recipient: %{email: "qa@example.test"}) |> render_submit()
    assert render(view) =~ "qa@example.test"
    view |> form("#tag-form", tag: %{name: "Donors"}) |> render_submit()
    assert render(view) =~ "Donors"
  end

  test "every admin page has a help guide behind the same help icon" do
    test_recipient_fixture()
    campaign = campaign_fixture()

    for path <- ["", "/sent", "/audience", "/campaigns/new", "/campaigns/#{campaign.id}"] do
      {:ok, view, _} = live(admin_conn(), "/admin/contact" <> path)
      assert has_element?(view, "#cc-help-toggle[aria-controls=cc-help]"), path
      assert has_element?(view, "#cc-help.hidden", "How this page works"), path
    end
  end

  test "audience page unsubscribes a person in one click" do
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")
    assert view |> element("#unsubscribe-2") |> render_click() =~ "Unsubscribed bob@example.com"
    refute has_element?(view, "#unsubscribe-2")
    assert has_element?(view, "#unsubscribe-1 svg")
    assert CustomerContact.Audience.suppressed?("bob@example.com")
    assert [%{email: "alice@example.com"}] = CustomerContact.Audience.deliverable_recipients(["all"])
  end

  test "sent page lists emails across campaigns and filters by address" do
    test_recipient_fixture()
    {:ok, campaign, _} = CustomerContact.Campaigns.send_test(campaign_fixture(), "a")
    {:ok, campaign} = CustomerContact.Campaigns.approve(campaign, "a", "2")
    {:ok, campaign} = CustomerContact.Campaigns.start_send(campaign, "a")
    :ok = perform_job(CustomerContact.Workers.Dispatch, %{campaign_id: campaign.id})

    {:ok, view, html} = live(admin_conn(), "/admin/contact/sent")
    assert html =~ "alice@example.com"
    assert html =~ "bob@example.com"
    refute html =~ "tester@example.test"

    html = view |> form("#sent-filters", email: "BOB") |> render_change()
    assert_patch(view, "/admin/contact/sent?email=BOB")
    assert html =~ "bob@example.com"
    refute html =~ "alice@example.com"

    {:ok, _view, html} = live(admin_conn(), "/admin/contact/sent?test=true&campaign=#{campaign.id}")
    assert html =~ "tester@example.test"
    refute html =~ "alice@example.com"

    {:ok, _view, html} = live(admin_conn(), "/admin/contact/sent?email=%25&status=nonsense&campaign=nope")
    assert html =~ "No emails match."
  end

  test "tampered admin events are refused without crashing the page" do
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")
    render_click(view, "delete_test", %{"id" => "not-a-uuid"})
    render_click(view, "unsuppress", %{"id" => "not-a-uuid"})
    assert render_click(view, "unsubscribe", %{"ref" => "no-such-ref"}) =~ "Couldn&#39;t unsubscribe"

    {:ok, view, _} = live(admin_conn(), "/admin/contact/campaigns/new")

    for event <- ~w(send_test approve revoke send) do
      assert render_click(view, event, %{}) =~ "Save the campaign first."
    end

    {:ok, view, _} = live(admin_conn(), "/admin/contact/campaigns/#{campaign_fixture().id}")
    assert render_click(view, "approve", %{}) =~ "alert"
  end

  test "duplicate makes a new draft with the same content and no history" do
    test_recipient_fixture()
    {:ok, original, _} = CustomerContact.Campaigns.send_test(campaign_fixture(), "a")
    {:ok, original} = CustomerContact.Campaigns.approve(original, "a", "2")

    {:ok, view, _} = live(admin_conn(), "/admin/contact/campaigns/#{original.id}")
    {:error, {:live_redirect, %{to: to}}} = view |> element("#duplicate-campaign") |> render_click()
    "/admin/contact/campaigns/" <> copy_id = to
    copy = CustomerContact.Campaigns.get_campaign!(copy_id)

    assert copy.name == "Copy of " <> original.name

    assert {copy.subject, copy.html_body, copy.layout, copy.segment_ids} ==
             {original.subject, original.html_body, original.layout, original.segment_ids}

    assert %{status: "draft", tested_at: nil, approved_by: nil} = copy
    assert CustomerContact.Campaigns.get_campaign!(original.id).status == "approved"

    {:ok, view, _} = live(admin_conn(), "/admin/contact")
    {:error, {:live_redirect, _}} = view |> element("#duplicate-#{original.id}") |> render_click()
    assert length(CustomerContact.Campaigns.list_campaigns()) == 3
  end

  test "admins can add a person by hand, who then receives campaigns" do
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")

    html = view |> form("#contact-form", contact: %{email: "new@example.org", name: "Nina New"}) |> render_submit()
    assert html =~ "confirm they agreed to receive emails"
    assert CustomerContact.Audience.list_contacts() == []

    html =
      view
      |> form("#contact-form", contact: %{email: "Alice@example.com", consent: "true"})
      |> render_submit()

    assert html =~ "is already in the audience"

    html =
      view
      |> form("#contact-form", contact: %{email: " New@Example.org ", name: "Nina New", consent: "true"})
      |> render_submit()

    assert html =~ "Added new@example.org."

    assert [%{email: "new@example.org", added_by: "admin@example.test"} = contact] =
             CustomerContact.Audience.list_contacts()

    assert contact.consent_note =~ "admin@example.test"
    assert html =~ "Added manually"
    assert html =~ "added manually"

    emails = &Enum.map(CustomerContact.Audience.deliverable_recipients(&1), fn r -> r.email end)
    assert "new@example.org" in emails.(["all"])
    assert emails.(["manual"]) == ["new@example.org"]
    refute "new@example.org" in emails.(["tag:" <> Ecto.UUID.generate()])

    view |> element("#delete-contact-#{contact.id}") |> render_click()
    assert CustomerContact.Audience.list_contacts() == []
    refute "new@example.org" in emails.(["all"])
  end

  defp upload_csv(view, content) do
    file_input(view, "#import-form", :csv, [%{name: "people.csv", content: content, type: "text/csv"}])
  end

  test "admins can import people from a CSV file and tag them" do
    {:ok, tag} = CustomerContact.Audience.create_tag(%{name: "Fair 2026"})
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")
    assert has_element?(view, "#import-guide")
    csv = "Email,Name\r\nnew@example.org,Nina New\r\nbob@example.com,Bob\r\nnot-an-email,X\r\nNEW@example.org,Again\r\n"

    upload = upload_csv(view, csv)
    render_upload(upload, "people.csv")
    html = view |> form("#import-form", import: %{tag_id: tag.id}) |> render_submit()
    assert html =~ "Confirm that everyone in the file agreed"
    assert CustomerContact.Audience.list_contacts() == []

    html = view |> form("#import-form", import: %{tag_id: tag.id, consent: "true"}) |> render_submit()
    assert html =~ "Imported 1 new person; 1 already in the audience. Skipped 1 row without a valid email."
    assert has_element?(view, "#import-result", "2 newly tagged")

    assert [%{email: "new@example.org", name: "Nina New", added_by: "admin@example.test"} = contact] =
             CustomerContact.Audience.list_contacts()

    assert contact.consent_note =~ "CSV import"
    tagged = CustomerContact.Audience.deliverable_recipients(["tag:" <> tag.id]) |> Enum.map(& &1.email) |> Enum.sort()
    assert tagged == ["bob@example.com", "new@example.org"]

    # Importing again adds and tags no one twice.
    render_upload(upload_csv(view, csv), "people.csv")
    html = view |> form("#import-form", import: %{tag_id: tag.id, consent: "true"}) |> render_submit()
    assert html =~ "Imported 0 new people; 2 already in the audience."
    assert has_element?(view, "#import-result", "0 newly tagged")
  end

  test "a CSV import without an email column or with an unknown tag imports no one" do
    {:ok, view, _} = live(admin_conn(), "/admin/contact/audience")

    render_upload(upload_csv(view, "name\nJane\n"), "people.csv")
    html = view |> form("#import-form", import: %{consent: "true"}) |> render_submit()
    assert html =~ "The first row must be a header with an email column."

    assert {:error, :unknown_tag} =
             CustomerContact.Audience.import_contacts(
               [%{line: 2, email: "a@example.com", name: nil}],
               "admin",
               Ecto.UUID.generate()
             )

    assert CustomerContact.Audience.list_contacts() == []
  end
end
