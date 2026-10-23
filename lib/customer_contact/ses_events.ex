defmodule CustomerContact.SESEvents do
  @moduledoc """
  Applies SES notifications (delivery, bounce, complaint, reject) to
  deliveries. Accepts both configuration-set event publishing (`eventType`) and
  identity notifications (`notificationType`).

  Permanent bounces and complaints add the address to the suppression list.
  """

  import Ecto.Query

  alias CustomerContact.{Audience, Delivery, Tracking}

  def handle(%{"mail" => %{"messageId" => message_id}} = event) do
    type = event["eventType"] || event["notificationType"]
    deliveries = CustomerContact.repo().all(from d in Delivery, where: d.provider_message_id == ^message_id)
    Enum.each(deliveries, &apply_event(type, &1, event))
    :ok
  end

  def handle(_), do: :ok

  defp apply_event("Delivery", delivery, event) do
    set_status(delivery, ["sent"], status: "delivered", delivered_at: now())
    Tracking.insert_event(delivery.id, "delivery", %{detail: %{"smtp" => get_in(event, ["delivery", "smtpResponse"])}})
  end

  defp apply_event("Bounce", delivery, event) do
    bounce = event["bounce"] || %{}
    permanent? = bounce["bounceType"] == "Permanent"

    if permanent? do
      set_status(delivery, ["sent", "delivered"], status: "bounced", bounced_at: now())

      for %{"emailAddress" => email} <- bounce["bouncedRecipients"] || [] do
        Audience.suppress(email, "bounce", "SES #{bounce["bounceSubType"]}")
      end
    end

    Tracking.insert_event(delivery.id, if(permanent?, do: "bounce", else: "soft_bounce"), %{
      detail: Map.take(bounce, ["bounceType", "bounceSubType"])
    })
  end

  defp apply_event("Complaint", delivery, event) do
    complaint = event["complaint"] || %{}
    set_status(delivery, ["sent", "delivered"], status: "complained", complained_at: now())

    for %{"emailAddress" => email} <- complaint["complainedRecipients"] || [] do
      Audience.suppress(email, "complaint", "SES complaint")
    end

    Tracking.insert_event(delivery.id, "complaint", %{detail: Map.take(complaint, ["complaintFeedbackType"])})
  end

  defp apply_event(type, delivery, event) when type in ["Reject", "Rendering Failure"] do
    set_status(delivery, ["sent"], status: "failed", error: "SES #{type}")
    Tracking.insert_event(delivery.id, "reject", %{detail: Map.take(event["reject"] || %{}, ["reason"])})
  end

  defp apply_event(_type, _delivery, _event), do: :ok

  defp set_status(%Delivery{id: id}, from_statuses, fields) do
    from(d in Delivery, where: d.id == ^id and d.status in ^from_statuses)
    |> CustomerContact.repo().update_all(set: Keyword.put(fields, :updated_at, now()))
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
