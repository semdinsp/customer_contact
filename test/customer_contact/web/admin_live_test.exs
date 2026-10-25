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
end
