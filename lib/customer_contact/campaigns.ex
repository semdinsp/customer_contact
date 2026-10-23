defmodule CustomerContact.Campaigns do
  @moduledoc """
  Campaign workflow: draft -> test send -> approve -> send.

    * A test send records a hash of the content. Editing the subject,
      preheader, HTML or layout afterwards invalidates the test.
    * Approval requires a valid test and the approver typing the number of
      recipients. Editing content or audience afterwards drops the campaign
      back to draft.
    * Sending requires a current approval and runs in Oban.
  """

  import Ecto.Query

  alias CustomerContact.{Audience, Campaign, Delivery, Sender}
  alias CustomerContact.Workers.Dispatch

  def list_campaigns, do: repo().all(from c in Campaign, order_by: [desc: c.inserted_at])

  def get_campaign!(id), do: repo().get!(Campaign, id)

  def change_campaign(%Campaign{} = campaign, attrs \\ %{}), do: Campaign.changeset(campaign, attrs)

  def create_campaign(attrs, actor) do
    %Campaign{created_by: actor}
    |> Campaign.changeset(attrs)
    |> repo().insert()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    if Campaign.editable?(campaign) do
      changeset = Campaign.changeset(campaign, attrs)

      with {:ok, updated} <- repo().update(changeset) do
        if updated.status == "approved" and not Campaign.approved?(updated) do
          revoke_approval(updated)
        else
          {:ok, updated}
        end
      end
    else
      {:error, :not_editable}
    end
  end

  def delete_campaign(%Campaign{status: "draft"} = campaign), do: repo().delete(campaign)
  def delete_campaign(%Campaign{}), do: {:error, :not_editable}

  @doc "Sends the campaign to every test recipient, synchronously."
  def send_test(%Campaign{} = campaign, actor) do
    test_recipients = Audience.list_test_recipients()

    cond do
      not Campaign.editable?(campaign) -> {:error, :not_editable}
      blank?(campaign.subject) -> {:error, :missing_subject}
      blank?(campaign.html_body) -> {:error, :missing_body}
      test_recipients == [] -> {:error, :no_test_recipients}
      true -> do_send_test(campaign, test_recipients, actor)
    end
  end

  defp do_send_test(campaign, test_recipients, actor) do
    results =
      Enum.map(test_recipients, fn tr ->
        delivery =
          repo().insert!(%Delivery{
            campaign_id: campaign.id,
            test: true,
            channel: campaign.channel,
            email: tr.email,
            name: tr.name,
            status: "sending"
          })

        case Sender.deliver(delivery, campaign) do
          :ok ->
            {tr.email, :ok}

          {:error, message} ->
            Sender.mark(delivery, status: "failed", error: message)
            {tr.email, {:error, message}}
        end
      end)

    if Enum.any?(results, &match?({_, :ok}, &1)) do
      {:ok, campaign} =
        campaign
        |> Ecto.Changeset.change(tested_hash: Campaign.content_hash(campaign), tested_at: now(), tested_by: actor)
        |> repo().update()

      {:ok, campaign, results}
    else
      {:error, {:send_failed, results}}
    end
  end

  @doc """
  Approves a tested draft. `typed_count` must equal the current number of
  deliverable recipients, as a guard against sending to the wrong list.
  """
  def approve(%Campaign{} = campaign, actor, typed_count) do
    count = Audience.count_deliverable(campaign.segment_ids)

    cond do
      campaign.status != "draft" ->
        {:error, :not_draft}

      not Campaign.tested?(campaign) ->
        {:error, :not_tested}

      campaign.segment_ids == [] ->
        {:error, :no_audience}

      count == 0 ->
        {:error, :no_recipients}

      parse_int(typed_count) != count ->
        {:error, {:count_mismatch, count}}

      true ->
        campaign
        |> Ecto.Changeset.change(
          status: "approved",
          approved_hash: Campaign.approval_hash(campaign),
          approved_count: count,
          approved_at: now(),
          approved_by: actor
        )
        |> repo().update()
    end
  end

  def revoke_approval(%Campaign{status: "approved"} = campaign) do
    campaign
    |> Ecto.Changeset.change(
      status: "draft",
      approved_hash: nil,
      approved_count: nil,
      approved_at: nil,
      approved_by: nil
    )
    |> repo().update()
  end

  def revoke_approval(%Campaign{} = campaign), do: {:ok, campaign}

  @doc "Starts sending an approved campaign. Safe against double clicks."
  def start_send(%Campaign{} = campaign, actor) do
    if Campaign.approved?(campaign) do
      repo().transaction(fn ->
        {count, _} =
          from(c in Campaign,
            where: c.id == ^campaign.id and c.status == "approved" and c.approved_hash == ^campaign.approved_hash
          )
          |> repo().update_all(set: [status: "sending", send_started_at: now(), sent_by: actor, updated_at: now()])

        if count == 1 do
          {:ok, _job} =
            Oban.insert(
              CustomerContact.oban(),
              Dispatch.new(%{campaign_id: campaign.id}, queue: CustomerContact.queue())
            )

          repo().get!(Campaign, campaign.id)
        else
          repo().rollback(:not_approved)
        end
      end)
    else
      {:error, :not_approved}
    end
  end

  @doc "Stops a send in progress. Deliveries already sent are unaffected."
  def cancel(%Campaign{status: "sending"} = campaign) do
    repo().transaction(fn ->
      from(c in Campaign, where: c.id == ^campaign.id and c.status == "sending")
      |> repo().update_all(set: [status: "cancelled", send_completed_at: now(), updated_at: now()])

      from(d in Delivery, where: d.campaign_id == ^campaign.id and d.status == "queued")
      |> repo().update_all(set: [status: "cancelled", updated_at: now()])

      repo().get!(Campaign, campaign.id)
    end)
  end

  def cancel(%Campaign{}), do: {:error, :not_sending}

  @doc false
  def maybe_complete(campaign_id) do
    pending =
      from(d in Delivery,
        where: d.campaign_id == ^campaign_id and d.test == false and d.status in ["queued", "sending"]
      )
      |> repo().exists?()

    unless pending do
      from(c in Campaign, where: c.id == ^campaign_id and c.status == "sending")
      |> repo().update_all(set: [status: "sent", send_completed_at: now(), updated_at: now()])
    end

    :ok
  end

  ## Reporting

  @doc "Counts for a campaign's real (non-test) deliveries."
  def stats(campaign_id) do
    row =
      from(d in Delivery,
        where: d.campaign_id == ^campaign_id and d.test == false,
        select: %{
          total: count(d.id),
          queued: filter(count(d.id), d.status in ["queued", "sending"]),
          sent: filter(count(d.id), d.status in ["sent", "delivered", "bounced", "complained"]),
          delivered: filter(count(d.id), d.status in ["delivered", "complained"]),
          bounced: filter(count(d.id), d.status == "bounced"),
          complained: filter(count(d.id), d.status == "complained"),
          failed: filter(count(d.id), d.status == "failed"),
          cancelled: filter(count(d.id), d.status == "cancelled"),
          opened: filter(count(d.id), not is_nil(d.first_opened_at)),
          clicked: filter(count(d.id), not is_nil(d.first_clicked_at)),
          unsubscribed: filter(count(d.id), not is_nil(d.unsubscribed_at))
        }
      )
      |> repo().one()

    row
  end

  def list_deliveries(campaign_id, opts \\ []) do
    test? = Keyword.get(opts, :test, false)
    limit = Keyword.get(opts, :limit, 200)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)

    from(d in Delivery,
      where: d.campaign_id == ^campaign_id and d.test == ^test?,
      order_by: [asc: d.email],
      limit: ^limit,
      offset: ^offset
    )
    |> then(fn q -> if status, do: where(q, [d], d.status == ^status), else: q end)
    |> repo().all()
  end

  defp blank?(value), do: value in [nil, ""] or String.trim(value) == ""

  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.replace(String.trim(s), ",", "")) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp repo, do: CustomerContact.repo()
end
