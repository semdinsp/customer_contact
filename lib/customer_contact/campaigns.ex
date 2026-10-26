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

  alias CustomerContact.{Audience, Campaign, Delivery, Log, Sender}
  alias CustomerContact.Workers.Dispatch

  def list_campaigns, do: repo().all(from c in Campaign, order_by: [desc: c.inserted_at])

  def get_campaign!(id), do: repo().get!(Campaign, id)

  def change_campaign(%Campaign{} = campaign, attrs \\ %{}), do: Campaign.changeset(campaign, attrs)

  def create_campaign(attrs, actor) do
    %Campaign{created_by: actor}
    |> Campaign.changeset(attrs)
    |> repo().insert()
  end

  @doc """
  Creates a new draft from a campaign's saved content and audience. Test,
  approval and send history are not copied, so the copy goes through the
  whole workflow again.
  """
  def duplicate_campaign(%Campaign{id: id}, actor) do
    source = get_campaign!(id)

    create_campaign(
      %{
        name: String.slice("Copy of " <> source.name, 0, 200),
        subject: source.subject,
        preheader: source.preheader,
        html_body: source.html_body,
        layout: source.layout,
        segment_ids: source.segment_ids
      },
      actor
    )
  end

  # Every workflow step re-reads and row-locks the campaign, so a stale copy
  # (e.g. an editor tab opened before someone else clicked Send) can never
  # change a campaign that has moved on.
  defp locked(%Campaign{id: id}, fun) do
    repo().transaction(fn ->
      campaign = repo().one!(from c in Campaign, where: c.id == ^id, lock: "FOR UPDATE")

      case fun.(campaign) do
        {:ok, result} -> result
        {:error, reason} -> repo().rollback(reason)
      end
    end)
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    locked(campaign, fn current ->
      if Campaign.editable?(current) do
        with {:ok, updated} <- repo().update(Campaign.changeset(current, attrs)) do
          if updated.status == "approved" and not Campaign.approved?(updated),
            do: do_revoke(updated),
            else: {:ok, updated}
        end
      else
        {:error, :not_editable}
      end
    end)
  end

  def delete_campaign(%Campaign{id: id}) do
    case repo().delete_all(from c in Campaign, where: c.id == ^id and c.status == "draft") do
      {1, _} -> {:ok, id}
      _ -> {:error, :not_editable}
    end
  end

  @doc """
  Sends the campaign to every test recipient, synchronously. The content is
  marked tested only if it is unchanged when the sends finish.
  """
  def send_test(%Campaign{id: id}, actor) do
    campaign = get_campaign!(id)
    test_recipients = Audience.list_test_recipients()

    cond do
      not Campaign.editable?(campaign) -> {:error, :not_editable}
      blank?(campaign.subject) -> {:error, :missing_subject}
      blank?(campaign.html_body) -> {:error, :missing_body}
      test_recipients == [] -> {:error, :no_test_recipients}
      true -> do_send_test(campaign, test_recipients, actor)
    end
    |> log_refusal("test send", campaign.id, actor)
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

    failed = Enum.count(results, &match?({_, {:error, _}}, &1))

    Log.info("test send finished",
      campaign_id: campaign.id,
      by: actor,
      sent: length(results) - failed,
      failed: failed
    )

    if Enum.any?(results, &match?({_, :ok}, &1)) do
      tested_hash = Campaign.content_hash(campaign)

      result =
        locked(campaign, fn current ->
          if Campaign.editable?(current) and Campaign.content_hash(current) == tested_hash do
            current
            |> Ecto.Changeset.change(tested_hash: tested_hash, tested_at: now(), tested_by: actor)
            |> repo().update()
          else
            {:error, :changed_during_test}
          end
        end)

      with {:ok, campaign} <- result, do: {:ok, campaign, results}
    else
      {:error, {:send_failed, results}}
    end
  end

  @doc """
  Approves a tested draft. `typed_count` must equal the current number of
  deliverable recipients, as a guard against sending to the wrong list.
  Refused while the host's brand has no postal address, which bulk email
  must include (CAN-SPAM, CASL).

  `seen` is the campaign as the approver saw it. If someone else has changed
  the content or audience since, approval is refused, so nobody approves
  content they haven't looked at.
  """
  def approve(%Campaign{} = seen, actor, typed_count) do
    seen
    |> locked(fn campaign ->
      count = Audience.count_deliverable(campaign.segment_ids)

      cond do
        campaign.status != "draft" ->
          {:error, :not_draft}

        Campaign.approval_hash(campaign) != Campaign.approval_hash(seen) ->
          {:error, :changed_elsewhere}

        not postal_address?() ->
          {:error, :missing_postal_address}

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
          |> tap(fn _ -> Log.info("campaign approved", campaign_id: campaign.id, by: actor, recipients: count) end)
      end
    end)
    |> log_refusal("approval", seen.id, actor)
  end

  def revoke_approval(%Campaign{} = campaign), do: locked(campaign, &do_revoke/1)

  defp do_revoke(%Campaign{status: "approved"} = campaign) do
    Log.info("approval revoked", campaign_id: campaign.id)

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

  defp do_revoke(%Campaign{} = campaign), do: {:ok, campaign}

  @doc """
  Starts sending an approved campaign. Safe against double clicks. If the
  audience size no longer matches the approved count, approval is revoked
  and nothing is sent. Like `approve/3`, refused if the campaign differs from
  `seen`, the copy the sender was looking at.
  """
  def start_send(%Campaign{} = seen, actor) do
    count = Audience.count_deliverable(seen.segment_ids)

    result =
      locked(seen, fn campaign ->
        cond do
          not Campaign.approved?(campaign) ->
            {:error, :not_approved}

          Campaign.approval_hash(seen) != campaign.approved_hash ->
            {:error, :changed_elsewhere}

          not postal_address?() ->
            {:error, :missing_postal_address}

          count != campaign.approved_count ->
            Log.warning("send refused: audience changed since approval",
              campaign_id: campaign.id,
              approved: campaign.approved_count,
              now: count
            )

            {:ok, _} = do_revoke(campaign)
            {:ok, {:audience_changed, campaign.approved_count, count}}

          true ->
            {:ok, campaign} =
              campaign
              |> Ecto.Changeset.change(status: "sending", send_started_at: now(), sent_by: actor)
              |> repo().update()

            {:ok, _job} =
              Oban.insert(
                CustomerContact.oban(),
                Dispatch.new(%{campaign_id: campaign.id}, queue: CustomerContact.queue())
              )

            Log.info("send started", campaign_id: campaign.id, by: actor, recipients: count)
            {:ok, campaign}
        end
      end)

    case result do
      {:ok, {:audience_changed, _, _} = reason} -> {:error, reason}
      other -> other
    end
    |> log_refusal("send", seen.id, actor)
  end

  # Refused clicks only show the admin a message, so log them too: otherwise
  # "I clicked and nothing happened" leaves no trace.
  defp log_refusal({:error, reason} = result, action, campaign_id, actor) do
    Log.info("#{action} refused", campaign_id: campaign_id, by: actor, reason: refusal_reason(reason))
    result
  end

  defp log_refusal(result, _action, _campaign_id, _actor), do: result

  # Test send failures carry per-recipient results; log only the count.
  defp refusal_reason({:send_failed, results}), do: "send_failed to #{length(results)} test recipients"
  defp refusal_reason({reason, _, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp refusal_reason({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp refusal_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp refusal_reason(_), do: "other"

  @doc false
  # Stops a send that can no longer be trusted (content or audience changed).
  def abort(campaign_id, note) do
    Log.warning("send stopped", campaign_id: campaign_id, reason: note)

    from(c in Campaign, where: c.id == ^campaign_id and c.status == "sending")
    |> repo().update_all(set: [status: "cancelled", note: note, send_completed_at: now(), updated_at: now()])

    from(d in Delivery, where: d.campaign_id == ^campaign_id and d.status == "queued")
    |> repo().update_all(set: [status: "cancelled", updated_at: now()])

    :ok
  end

  @doc "Stops a send in progress. Deliveries already sent are unaffected."
  def cancel(%Campaign{status: "sending"} = campaign) do
    repo().transaction(fn ->
      from(c in Campaign, where: c.id == ^campaign.id and c.status == "sending")
      |> repo().update_all(set: [status: "cancelled", send_completed_at: now(), updated_at: now()])

      from(d in Delivery, where: d.campaign_id == ^campaign.id and d.status == "queued")
      |> repo().update_all(set: [status: "cancelled", updated_at: now()])

      Log.info("send cancelled", campaign_id: campaign.id)
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
      {completed, _} =
        from(c in Campaign, where: c.id == ^campaign_id and c.status == "sending")
        |> repo().update_all(set: [status: "sent", send_completed_at: now(), updated_at: now()])

      if completed == 1 do
        stats = stats(campaign_id)

        Log.info("campaign sent",
          campaign_id: campaign_id,
          sent: stats.sent,
          failed: stats.failed,
          cancelled: stats.cancelled
        )
      end
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

  @doc """
  Emails sent across all campaigns, newest first, with `campaign` preloaded.

  Options: `:email` (case-insensitive, matches part of the address),
  `:campaign_id`, `:status`, `:test` (default `false`), `:limit` (default 200).
  """
  def list_sent(opts \\ []) do
    test? = Keyword.get(opts, :test, false)
    email = opts |> Keyword.get(:email, "") |> to_string() |> String.trim()

    from(d in Delivery,
      join: c in assoc(d, :campaign),
      where: d.test == ^test?,
      order_by: [desc: d.inserted_at, asc: d.email],
      limit: ^Keyword.get(opts, :limit, 200),
      preload: [campaign: c]
    )
    |> then(fn q -> if email != "", do: where(q, [d], ilike(d.email, ^"%#{escape_like(email)}%")), else: q end)
    |> then(fn q -> if id = opts[:campaign_id], do: where(q, [d], d.campaign_id == ^id), else: q end)
    |> then(fn q -> if status = opts[:status], do: where(q, [d], d.status == ^status), else: q end)
    |> repo().all()
  end

  defp escape_like(text), do: String.replace(text, ~w(\\ % _), &("\\" <> &1))

  @doc "True when the host's brand includes the postal address the email footer must show."
  def postal_address?, do: not blank?(CustomerContact.brand()[:postal_address])

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
