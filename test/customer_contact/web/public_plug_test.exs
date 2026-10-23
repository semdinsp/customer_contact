defmodule CustomerContact.Web.PublicPlugTest do
  use CustomerContact.DataCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias CustomerContact.{Audience, Delivery, SNS, Tracking}

  @endpoint CustomerContact.TestEndpoint
  @topic "arn:aws:sns:us-east-1:111111111111:test-ses-events"
  @cert_url "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-test.pem"

  setup do
    campaign = campaign_fixture()

    delivery =
      Repo.insert!(%Delivery{
        campaign_id: campaign.id,
        email: "jo@example.com",
        status: "sent",
        provider_message_id: "ses-msg-1"
      })

    %{delivery: delivery}
  end

  defp path(url), do: URI.parse(url).path

  test "open pixel records an open and always returns a gif", %{delivery: d} do
    conn = get(build_conn(), path(Tracking.open_url(d.id)))
    assert response(conn, 200)
    assert response_content_type(conn, :gif) =~ "image/gif"
    get(build_conn(), path(Tracking.open_url(d.id)))
    assert %{open_count: 2, first_opened_at: %DateTime{}} = Repo.get!(Delivery, d.id)
    # Replays bump the counter but don't add event rows.
    assert Repo.aggregate(CustomerContact.Event, :count) == 1

    assert response(get(build_conn(), "/cc/o/forged.gif"), 200)
  end

  test "click redirects to the signed url and records a click", %{delivery: d} do
    conn = get(build_conn(), path(Tracking.click_url(d.id, "https://example.org/x")))
    assert redirected_to(conn, 302) == "https://example.org/x"
    assert %{click_count: 1, first_opened_at: %DateTime{}} = Repo.get!(Delivery, d.id)
  end

  test "forged click tokens are not redirected" do
    assert response(get(build_conn(), "/cc/c/forged"), 404)
  end

  test "unsubscribe GET only confirms; POST suppresses", %{delivery: d} do
    url = path(Tracking.unsubscribe_url(d.id))
    refute url =~ Base.url_encode64("jo@example.com", padding: false)
    conn = get(build_conn(), url)
    assert html_response(conn, 200) =~ "Unsubscribe <strong>jo@example.com</strong>"
    refute Audience.suppressed?("jo@example.com")

    conn = post(build_conn(), url, %{"List-Unsubscribe" => "One-Click"})
    assert html_response(conn, 200) =~ "will no longer receive"
    assert Audience.suppressed?("jo@example.com")
    assert %{unsubscribed_at: %DateTime{}} = Repo.get!(Delivery, d.id)
  end

  describe "SNS" do
    setup do
      %{cert: der, key: key} = :public_key.pkix_test_root_cert(~c"SNS test", key: {:rsa, 2048, 65537})
      pem = :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
      Application.put_env(:customer_contact, :sns_cert_fetcher, fn @cert_url -> {:ok, pem} end)
      :persistent_term.erase({SNS, @cert_url})
      :persistent_term.erase({SNS, :cert_fetches})

      on_exit(fn ->
        Application.delete_env(:customer_contact, :sns_cert_fetcher)
        :persistent_term.erase({SNS, @cert_url})
        :persistent_term.erase({SNS, :cert_fetches})
      end)

      %{key: key}
    end

    defp sns_message(key, event, overrides \\ %{}) do
      msg =
        Map.merge(
          %{
            "Type" => "Notification",
            "MessageId" => "m1",
            "TopicArn" => @topic,
            "Message" => Jason.encode!(event),
            "Timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
            "SignatureVersion" => "2",
            "SigningCertURL" => @cert_url
          },
          overrides
        )

      Map.put(msg, "Signature", Base.encode64(:public_key.sign(SNS.string_to_sign(msg), :sha256, key)))
    end

    defp post_sns(msg) do
      build_conn()
      |> put_req_header("content-type", "text/plain; charset=UTF-8")
      |> post("/cc/sns", Jason.encode!(msg))
    end

    test "permanent bounce marks the delivery bounced and suppresses", %{key: key, delivery: d} do
      event = %{
        "eventType" => "Bounce",
        "mail" => %{"messageId" => "ses-msg-1"},
        "bounce" => %{
          "bounceType" => "Permanent",
          "bounceSubType" => "General",
          "bouncedRecipients" => [%{"emailAddress" => "jo@example.com"}]
        }
      }

      assert response(post_sns(sns_message(key, event)), 200)
      assert %{status: "bounced"} = Repo.get!(Delivery, d.id)
      assert Audience.suppressed?("jo@example.com")
    end

    test "delivery event marks delivered", %{key: key, delivery: d} do
      event = %{"eventType" => "Delivery", "mail" => %{"messageId" => "ses-msg-1"}, "delivery" => %{}}
      assert response(post_sns(sns_message(key, event)), 200)
      assert %{status: "delivered"} = Repo.get!(Delivery, d.id)
    end

    test "tampered message is rejected", %{key: key, delivery: d} do
      msg = sns_message(key, %{"eventType" => "Delivery", "mail" => %{"messageId" => "ses-msg-1"}})

      msg =
        Map.put(msg, "Message", Jason.encode!(%{"eventType" => "Complaint", "mail" => %{"messageId" => "ses-msg-1"}}))

      assert response(post_sns(msg), 403)
      assert %{status: "sent"} = Repo.get!(Delivery, d.id)
    end

    test "messages from other topics are rejected even if validly signed", %{key: key} do
      msg = sns_message(key, %{}, %{"TopicArn" => "arn:aws:sns:us-east-1:999999999999:attacker"})
      assert response(post_sns(msg), 403)
    end

    test "certificates from non-AWS or look-alike hosts are rejected", %{key: key} do
      for url <- [
            "https://evil.example/SimpleNotificationService-x.pem",
            # S3 virtual-hosted bucket named "sns": matches a naive sns.*.amazonaws.com check
            "https://sns.s3.amazonaws.com/SimpleNotificationService-x.pem",
            # another region than the topic's
            "https://sns.eu-west-1.amazonaws.com/SimpleNotificationService-x.pem",
            "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-test.pem?n=1",
            "https://sns.us-east-1.amazonaws.com/other/path.pem",
            "https://user@sns.us-east-1.amazonaws.com/SimpleNotificationService-test.pem"
          ] do
        msg = sns_message(key, %{}, %{"SigningCertURL" => url})
        assert response(post_sns(msg), 403), url
      end
    end

    test "old messages are rejected so captured ones can't be replayed", %{key: key, delivery: d} do
      old = DateTime.utc_now() |> DateTime.add(-2, :hour) |> DateTime.to_iso8601()
      event = %{"eventType" => "Delivery", "mail" => %{"messageId" => "ses-msg-1"}, "delivery" => %{}}
      assert response(post_sns(sns_message(key, event, %{"Timestamp" => old})), 403)
      assert %{status: "sent"} = Repo.get!(Delivery, d.id)
    end

    test "fetches of uncached certificates are rate limited", %{key: key} do
      fetches = :counters.new(1, [])

      Application.put_env(:customer_contact, :sns_cert_fetcher, fn _ ->
        :counters.add(fetches, 1, 1)
        {:error, :cert_unavailable}
      end)

      statuses =
        for i <- 1..15 do
          url = "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-made#{i}up.pem"
          post_sns(sns_message(key, %{}, %{"SigningCertURL" => url})).status
        end

      assert Enum.all?(statuses, &(&1 == 503))
      assert :counters.get(fetches, 1) == 10
    end

    test "non-string fields are rejected, not crashed on", %{key: key} do
      msg = sns_message(key, %{}) |> Map.put("Subject", %{"x" => 1})
      assert response(post_sns(msg), 403)
    end
  end
end
