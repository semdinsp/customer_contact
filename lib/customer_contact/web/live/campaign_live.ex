defmodule CustomerContact.Web.CampaignLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.{Audience, Campaign, Campaigns, Email}

  @impl true
  def mount(params, _session, socket) do
    campaign =
      case socket.assigns.live_action do
        :new -> %Campaign{}
        :edit -> Campaigns.get_campaign!(params["id"])
      end

    {:ok,
     socket
     |> assign(page_title: campaign.name || "New campaign", segments: Audience.list_segments())
     |> assign(test_recipients: Audience.list_test_recipients())
     |> load(campaign)}
  end

  defp load(socket, %Campaign{} = campaign) do
    count = if campaign.id && campaign.segment_ids != [], do: Audience.count_deliverable(campaign.segment_ids), else: 0

    socket
    |> assign(campaign: campaign, dirty: false, deliverable_count: count)
    |> assign(form: to_form(Campaigns.change_campaign(campaign)))
    |> assign(preview: Email.preview_html(campaign))
  end

  @impl true
  def handle_event("validate", %{"campaign" => params}, socket) do
    changeset = Campaigns.change_campaign(socket.assigns.campaign, params) |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       form: to_form(changeset),
       dirty: changeset.changes != %{},
       preview: Email.preview_html(Ecto.Changeset.apply_changes(changeset))
     )}
  end

  def handle_event("save", %{"campaign" => params}, socket) do
    case socket.assigns.live_action do
      :new ->
        case Campaigns.create_campaign(params, socket.assigns.cc_actor) do
          {:ok, campaign} ->
            {:noreply,
             socket
             |> put_flash(:info, "Campaign saved.")
             |> push_navigate(to: socket.assigns.cc_base <> "/campaigns/" <> campaign.id)}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      :edit ->
        was_approved = socket.assigns.campaign.status == "approved"

        case Campaigns.update_campaign(socket.assigns.campaign, params) do
          {:ok, campaign} ->
            message =
              if was_approved and campaign.status == "draft",
                do: "Saved. Approval was cleared because the content or audience changed.",
                else: "Campaign saved."

            {:noreply, socket |> put_flash(:info, message) |> load(campaign)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}

          {:error, :not_editable} ->
            {:noreply, put_flash(socket, :error, "This campaign can no longer be edited.")}
        end
    end
  end

  def handle_event("send_test", _params, socket) do
    if socket.assigns.dirty do
      {:noreply, put_flash(socket, :error, "Save your changes before sending a test.")}
    else
      case Campaigns.send_test(socket.assigns.campaign, socket.assigns.cc_actor) do
        {:ok, campaign, results} ->
          failed = for {email, {:error, _}} <- results, do: email
          sent = length(results) - length(failed)

          msg =
            "Test sent to #{sent} test recipient(s)." <>
              if(failed == [], do: "", else: " Failed: #{Enum.join(failed, ", ")}")

          {:noreply, socket |> put_flash(:info, msg) |> load(campaign)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    end
  end

  def handle_event("approve", %{"count" => typed}, socket) do
    if socket.assigns.dirty do
      {:noreply, put_flash(socket, :error, "Save your changes before approving.")}
    else
      case Campaigns.approve(socket.assigns.campaign, socket.assigns.cc_actor, typed) do
        {:ok, campaign} ->
          {:noreply,
           socket |> put_flash(:info, "Approved for #{campaign.approved_count} recipients.") |> load(campaign)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    end
  end

  def handle_event("revoke", _params, socket) do
    {:ok, campaign} = Campaigns.revoke_approval(socket.assigns.campaign)
    {:noreply, socket |> put_flash(:info, "Approval revoked.") |> load(campaign)}
  end

  def handle_event("send", _params, socket) do
    campaign = Campaigns.get_campaign!(socket.assigns.campaign.id)

    case Campaigns.start_send(campaign, socket.assigns.cc_actor) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sending started.")
         |> push_navigate(to: socket.assigns.cc_base <> "/campaigns/" <> campaign.id <> "/report")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(reason)) |> load(Campaigns.get_campaign!(campaign.id))}
    end
  end

  def handle_event("delete", _params, socket) do
    case Campaigns.delete_campaign(socket.assigns.campaign) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Campaign deleted.") |> push_navigate(to: socket.assigns.cc_base)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Only draft campaigns can be deleted.")}
    end
  end

  defp error_message(:not_editable), do: "This campaign can no longer be changed."
  defp error_message(:missing_subject), do: "Add a subject first."
  defp error_message(:missing_body), do: "Add the email HTML first."
  defp error_message(:no_test_recipients), do: "Add test recipients on the Audience page first."

  defp error_message({:send_failed, results}),
    do: "Test send failed: " <> Enum.map_join(results, "; ", fn {e, {:error, m}} -> "#{e}: #{m}" end)

  defp error_message(:not_draft), do: "Only draft campaigns can be approved."
  defp error_message(:not_tested), do: "Send a test of the current content before approving."
  defp error_message(:no_audience), do: "Choose who to send to first."
  defp error_message(:no_recipients), do: "The chosen audience has no deliverable recipients."

  defp error_message({:count_mismatch, count}),
    do: "The number typed does not match the #{count} recipients. Not approved."

  defp error_message(:changed_during_test),
    do: "The campaign changed while the test was sending. Send another test of the current content."

  defp error_message({:audience_changed, approved, now}),
    do:
      "Not sent: the audience changed from #{approved} to #{now} recipients since approval. Approval was revoked; review and approve again."

  defp error_message(:not_approved), do: "This campaign is not approved (or changed since approval)."
  defp error_message(other), do: "Error: #{inspect(other)}"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        editable: Campaign.editable?(assigns.campaign),
        tested: assigns.campaign.id && Campaign.tested?(assigns.campaign),
        approved: assigns.campaign.id && Campaign.approved?(assigns.campaign),
        selected: assigns.form[:segment_ids].value || []
      )

    ~H"""
    <.shell flash={@flash} base={@cc_base} active={:campaigns}>
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <h2 class="text-lg font-semibold">{@campaign.name || "New campaign"}</h2>
        <.status_badge :if={@campaign.id} status={@campaign.status} />
        <span :if={@dirty} class="badge badge-warning">unsaved changes</span>
        <div class="grow"></div>
        <.link
          :if={@campaign.status in ~w(sending sent cancelled)}
          navigate={@cc_base <> "/campaigns/" <> @campaign.id <> "/report"}
          class="btn btn-sm"
        >
          View report
        </.link>
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <div>
          <.form for={@form} id="campaign-form" phx-change="validate" phx-submit="save">
            <fieldset disabled={not @editable} class="space-y-1">
              <.input field={@form[:name]} label="Internal name" />
              <.input field={@form[:subject]} label="Subject" placeholder="Supports {{first_name}}" />
              <.input field={@form[:preheader]} label="Preheader (inbox preview text)" />
              <fieldset class="fieldset">
                <label class="label" for="campaign_layout">Layout</label>
                <select id="campaign_layout" name={@form[:layout].name} class="select w-full">
                  <option value="branded" selected={@form[:layout].value == "branded"}>
                    Branded (wrap my HTML in the site's header and footer)
                  </option>
                  <option value="none" selected={@form[:layout].value == "none"}>
                    None (my HTML is a complete email; footer is appended)
                  </option>
                </select>
              </fieldset>
              <.input
                field={@form[:html_body]}
                type="textarea"
                label="Email HTML (merge fields: {{name}} {{first_name}} {{email}} {{unsubscribe_url}})"
                rows="16"
                phx-debounce="600"
              />

              <fieldset class="fieldset">
                <legend class="fieldset-legend">Send to</legend>
                <input type="hidden" name={@form[:segment_ids].name <> "[]"} value="" />
                <label :for={s <- @segments} class="label cursor-pointer justify-start gap-2">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    name={@form[:segment_ids].name <> "[]"}
                    value={s.id}
                    checked={s.id in @selected}
                  />
                  <span>{s.name}</span>
                  <span class="opacity-60">({s.count})</span>
                </label>
              </fieldset>

              <div class="flex gap-2 pt-2">
                <button type="submit" class="btn btn-primary" id="save-campaign">Save</button>
                <button
                  :if={@campaign.status == "draft"}
                  type="button"
                  phx-click="delete"
                  data-confirm="Delete this draft?"
                  class="btn btn-ghost text-error"
                >
                  Delete draft
                </button>
              </div>
            </fieldset>
          </.form>

          <div :if={@campaign.id && @editable} class="mt-8 space-y-4" id="workflow">
            <div class="card bg-base-200">
              <div class="card-body p-4">
                <h3 class="font-semibold">1. Send a test</h3>
                <p class="text-sm">
                  Test recipients: <span :if={@test_recipients == []} class="text-error">none —</span>
                  {Enum.map_join(@test_recipients, ", ", & &1.email)}
                  <.link navigate={@cc_base <> "/audience"} class="link">manage</.link>
                </p>
                <p :if={@tested} class="text-sm text-success" id="tested-status">
                  Current content tested by {@campaign.tested_by} at {format_time(@campaign.tested_at)}.
                </p>
                <p :if={!@tested && @campaign.tested_at} class="text-sm text-warning">
                  Content changed since the last test.
                </p>
                <div>
                  <button phx-click="send_test" class="btn btn-sm" id="send-test" disabled={@test_recipients == []}>
                    Send test
                  </button>
                </div>
              </div>
            </div>

            <div class="card bg-base-200">
              <div class="card-body p-4">
                <h3 class="font-semibold">2. Approve</h3>
                <%= if @approved do %>
                  <p class="text-sm text-success" id="approved-status">
                    Approved by {@campaign.approved_by} at {format_time(@campaign.approved_at)} for {@campaign.approved_count} recipients.
                  </p>
                  <div><button phx-click="revoke" class="btn btn-sm btn-ghost">Revoke approval</button></div>
                <% else %>
                  <p class="text-sm">
                    This will go to <strong id="deliverable-count">{@deliverable_count}</strong>
                    recipients (after removing duplicates and unsubscribed/bounced addresses).
                    Type that number to approve.
                  </p>
                  <form phx-submit="approve" class="flex gap-2" id="approve-form">
                    <input
                      type="text"
                      name="count"
                      inputmode="numeric"
                      autocomplete="off"
                      class="input input-sm w-32"
                      placeholder="count"
                    />
                    <button type="submit" class="btn btn-sm btn-secondary" disabled={!@tested}>Approve</button>
                  </form>
                  <p :if={!@tested} class="text-xs opacity-70">Send a test of the current content first.</p>
                <% end %>
              </div>
            </div>

            <div class="card bg-base-200">
              <div class="card-body p-4">
                <h3 class="font-semibold">3. Send</h3>
                <button
                  phx-click="send"
                  class="btn btn-error w-fit"
                  id="send-campaign"
                  disabled={!@approved or @dirty}
                  data-confirm={"Send this email to #{@campaign.approved_count} recipients now? This cannot be undone."}
                >
                  Send to {@campaign.approved_count || 0} recipients
                </button>
              </div>
            </div>
          </div>
        </div>

        <div>
          <h3 class="font-semibold mb-2">Preview</h3>
          <iframe
            id="preview"
            sandbox=""
            srcdoc={@preview}
            title="Email preview"
            class="w-full h-[800px] rounded border border-base-300 bg-white"
          ></iframe>
        </div>
      </div>
    </.shell>
    """
  end
end
