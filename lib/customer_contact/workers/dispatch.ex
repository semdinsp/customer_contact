defmodule CustomerContact.Workers.Dispatch do
  @moduledoc """
  Creates the deliveries for a campaign that has started sending and enqueues
  one `Deliver` job per delivery. Safe to retry: deliveries are unique per
  campaign and email, and `Deliver` claims each delivery atomically.
  """

  use Oban.Worker, queue: :customer_contact, max_attempts: 5

  import Ecto.Query

  alias CustomerContact.{Audience, Campaign, Campaigns, Delivery, Log}
  alias CustomerContact.Workers.Deliver

  @chunk 500

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    case CustomerContact.repo().get(Campaign, campaign_id) do
      %Campaign{status: "sending"} = campaign -> dispatch(campaign)
      _ -> :ok
    end
  end

  defp dispatch(campaign) do
    recipients = Audience.deliverable_recipients(campaign.segment_ids)

    cond do
      campaign.approved_hash != Campaign.approval_hash(campaign) ->
        Campaigns.abort(campaign.id, "Not sent: content or audience changed after approval.")

      length(recipients) != campaign.approved_count and not already_dispatched?(campaign) ->
        Campaigns.abort(
          campaign.id,
          "Not sent: audience changed from #{campaign.approved_count} to #{length(recipients)} recipients after approval."
        )

      true ->
        insert_and_enqueue(campaign, recipients)
    end
  end

  # On a retry the deliveries already exist (and some may have been sent and
  # their addresses since suppressed), so the count check only applies to the
  # first run.
  defp already_dispatched?(campaign) do
    from(d in Delivery, where: d.campaign_id == ^campaign.id and d.test == false)
    |> CustomerContact.repo().exists?()
  end

  defp insert_and_enqueue(campaign, recipients) do
    repo = CustomerContact.repo()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    recipients
    |> Enum.map(fn r ->
      %{
        id: Ecto.UUID.generate(),
        campaign_id: campaign.id,
        test: false,
        channel: campaign.channel,
        recipient_ref: r.ref,
        email: r.email,
        name: r.name,
        status: "queued",
        open_count: 0,
        click_count: 0,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(@chunk)
    |> Enum.each(&repo.insert_all(Delivery, &1, on_conflict: :nothing))

    queued =
      from(d in Delivery,
        where: d.campaign_id == ^campaign.id and d.test == false and d.status == "queued",
        select: d.id
      )
      |> repo.all()

    Log.info("dispatching campaign", campaign_id: campaign.id, recipients: length(recipients), queued: length(queued))

    queued
    |> Enum.map(&Deliver.new(%{delivery_id: &1}, queue: CustomerContact.queue()))
    |> Enum.chunk_every(@chunk)
    |> Enum.each(&Oban.insert_all(CustomerContact.oban(), &1))

    Campaigns.maybe_complete(campaign.id)
  end
end
