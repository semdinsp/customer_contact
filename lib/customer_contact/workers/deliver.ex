defmodule CustomerContact.Workers.Deliver do
  @moduledoc """
  Sends one delivery. The delivery is claimed (`queued` -> `sending`) with a
  conditional update before sending, so a duplicated job can never send the
  same email twice. Failures are retried; after the last attempt the delivery
  is marked `failed`.

  Throughput is set by the host's Oban queue concurrency; keep it under the
  SES sending rate for the account.
  """

  use Oban.Worker, queue: :customer_contact, max_attempts: 5

  import Ecto.Query

  alias CustomerContact.{Audience, Campaign, Campaigns, Delivery, Sender}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}} = job) do
    repo = CustomerContact.repo()

    with %Delivery{} = delivery <- repo.get(Delivery, delivery_id),
         %Campaign{} = campaign <- repo.get(Campaign, delivery.campaign_id) do
      result = run(delivery, campaign, job)
      Campaigns.maybe_complete(campaign.id)
      result
    else
      nil -> :ok
    end
  end

  defp run(delivery, %Campaign{status: status}, _job) when status != "sending" do
    if delivery.status == "queued", do: Sender.mark(delivery, status: "cancelled")
    :ok
  end

  defp run(delivery, campaign, job) do
    cond do
      not claim(delivery) ->
        :ok

      Audience.suppressed?(delivery.email) ->
        Sender.mark(delivery, status: "cancelled", error: "suppressed before send")
        :ok

      true ->
        case Sender.deliver(delivery, campaign) do
          :ok ->
            :ok

          {:error, message} ->
            if job.attempt >= job.max_attempts do
              Sender.mark(delivery, status: "failed", error: message)
              :ok
            else
              Sender.mark(delivery, status: "queued", error: message)
              {:error, message}
            end
        end
    end
  end

  defp claim(%Delivery{id: id}) do
    {count, _} =
      from(d in Delivery, where: d.id == ^id and d.status == "queued")
      |> CustomerContact.repo().update_all(
        set: [status: "sending", updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

    count == 1
  end
end
