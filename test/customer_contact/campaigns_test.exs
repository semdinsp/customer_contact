defmodule CustomerContact.CampaignsTest do
  use CustomerContact.DataCase, async: false

  alias CustomerContact.{Audience, Campaign, Campaigns, Delivery}
  alias CustomerContact.Workers.{Deliver, Dispatch}

  describe "audience" do
    test "dedupes by email, drops blanks and suppressed addresses" do
      assert Enum.map(Audience.deliverable_recipients(["all"]), & &1.email) == ["alice@example.com", "bob@example.com"]
      {:ok, _} = Audience.suppress("BOB@example.com", "unsubscribe")
      assert Enum.map(Audience.deliverable_recipients(["all"]), & &1.email) == ["alice@example.com"]
    end

    test "built-in tags select recipients by ref" do
      {:ok, tag} = Audience.create_tag(%{name: "VIP"})
      Audience.tag_recipient(tag.id, "2")
      assert [%{email: "bob@example.com"}] = Audience.deliverable_recipients(["tag:" <> tag.id])
      assert [%{name: "Everyone", count: 4}, %{name: "VIP", count: 1}] = Audience.list_segments()
    end
  end

  defp approved_campaign do
    test_recipient_fixture()
    {:ok, campaign, _} = Campaigns.send_test(campaign_fixture(), "a")
    assert_email_sent(subject: "[TEST] Hello Tester")
    {:ok, campaign} = Campaigns.approve(campaign, "a", "2")
    campaign
  end

  describe "workflow" do
    test "cannot approve before a test send" do
      campaign = campaign_fixture()
      assert {:error, :not_tested} = Campaigns.approve(campaign, "a", "2")
    end

    test "test send goes only to test recipients and marks content tested" do
      test_recipient_fixture()
      campaign = campaign_fixture()
      assert {:ok, campaign, [{"tester@example.test", :ok}]} = Campaigns.send_test(campaign, "a")
      assert Campaign.tested?(campaign)
      assert_email_sent(subject: "[TEST] Hello Tester", to: [{"Tester", "tester@example.test"}])
      refute_email_sent()
      assert [%Delivery{test: true, status: "sent"}] = Repo.all(Delivery)
    end

    test "approval requires the typed recipient count" do
      test_recipient_fixture()
      {:ok, campaign, _} = Campaigns.send_test(campaign_fixture(), "a")
      assert {:error, {:count_mismatch, 2}} = Campaigns.approve(campaign, "a", "3")
      assert {:ok, %{status: "approved", approved_count: 2}} = Campaigns.approve(campaign, "a", "2")
    end

    test "editing content after approval clears approval and invalidates the test" do
      test_recipient_fixture()
      {:ok, campaign, _} = Campaigns.send_test(campaign_fixture(), "a")
      {:ok, campaign} = Campaigns.approve(campaign, "a", "2")
      {:ok, campaign} = Campaigns.update_campaign(campaign, %{html_body: "<p>changed</p>"})
      assert campaign.status == "draft"
      refute Campaign.tested?(campaign)
      assert {:error, :not_approved} = Campaigns.start_send(campaign, "a")
    end

    test "changing the audience after approval clears approval but keeps the test" do
      test_recipient_fixture()
      {:ok, tag} = Audience.create_tag(%{name: "VIP"})
      {:ok, campaign, _} = Campaigns.send_test(campaign_fixture(), "a")
      {:ok, campaign} = Campaigns.approve(campaign, "a", "2")
      {:ok, campaign} = Campaigns.update_campaign(campaign, %{segment_ids: ["tag:" <> tag.id]})
      assert campaign.status == "draft"
      assert Campaign.tested?(campaign)
    end

    test "full send: dispatch, deliver once, complete" do
      campaign = approved_campaign()
      {:ok, campaign} = Campaigns.start_send(campaign, "sender")
      assert campaign.status == "sending"
      assert {:error, :not_approved} = Campaigns.start_send(campaign, "sender")

      assert_enqueued(worker: Dispatch, args: %{campaign_id: campaign.id})
      assert :ok = perform_job(Dispatch, %{campaign_id: campaign.id})
      # Dispatch is idempotent.
      assert :ok = perform_job(Dispatch, %{campaign_id: campaign.id})

      deliveries = Repo.all(from d in Delivery, where: d.test == false)
      assert length(deliveries) == 2

      for d <- deliveries do
        assert :ok = perform_job(Deliver, %{delivery_id: d.id})
        # A duplicate job must not send again.
        assert :ok = perform_job(Deliver, %{delivery_id: d.id})
      end

      assert_email_sent(to: [{"Alice Smith", "alice@example.com"}])
      assert_email_sent(to: [{"Bob", "bob@example.com"}])
      refute_email_sent()

      assert Campaigns.get_campaign!(campaign.id).status == "sent"
      assert %{sent: 2, total: 2} = Campaigns.stats(campaign.id)
    end

    test "cancel stops queued deliveries" do
      campaign = approved_campaign()
      {:ok, campaign} = Campaigns.start_send(campaign, "s")
      :ok = perform_job(Dispatch, %{campaign_id: campaign.id})
      {:ok, _} = Campaigns.cancel(campaign)

      for d <- Repo.all(from d in Delivery, where: d.test == false) do
        :ok = perform_job(Deliver, %{delivery_id: d.id})
      end

      refute_email_sent()
      assert %{cancelled: 2} = Campaigns.stats(campaign.id)
    end

    test "addresses suppressed after dispatch are skipped" do
      campaign = approved_campaign()
      {:ok, campaign} = Campaigns.start_send(campaign, "s")
      :ok = perform_job(Dispatch, %{campaign_id: campaign.id})
      {:ok, _} = Audience.suppress("bob@example.com", "unsubscribe")

      for d <- Repo.all(from d in Delivery, where: d.test == false) do
        :ok = perform_job(Deliver, %{delivery_id: d.id})
      end

      assert_email_sent(to: [{"Alice Smith", "alice@example.com"}])
      refute_email_sent()
    end
  end
end
