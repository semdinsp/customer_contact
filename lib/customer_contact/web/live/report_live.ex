defmodule CustomerContact.Web.ReportLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.{Campaigns, Delivery}

  @page 200
  @refresh_ms 5_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    campaign = Campaigns.get_campaign!(id)
    if connected?(socket), do: :timer.send_interval(@refresh_ms, :refresh)

    {:ok,
     socket
     |> assign(campaign: campaign, page_title: "Report: " <> campaign.name, status_filter: nil, limit: @page)
     |> load()}
  end

  defp load(socket) do
    %{campaign: campaign, status_filter: status, limit: limit} = socket.assigns
    campaign = Campaigns.get_campaign!(campaign.id)

    assign(socket,
      campaign: campaign,
      stats: Campaigns.stats(campaign.id),
      deliveries: Campaigns.list_deliveries(campaign.id, status: status, limit: limit),
      tests: Campaigns.list_deliveries(campaign.id, test: true, limit: 50)
    )
  end

  @impl true
  def handle_info(:refresh, socket) do
    if socket.assigns.campaign.status == "sending", do: {:noreply, load(socket)}, else: {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    status = if status in Delivery.statuses(), do: status
    {:noreply, socket |> assign(status_filter: status, limit: @page) |> load()}
  end

  def handle_event("more", _params, socket) do
    {:noreply, socket |> assign(limit: socket.assigns.limit + @page) |> load()}
  end

  def handle_event("cancel", _params, socket) do
    case Campaigns.cancel(socket.assigns.campaign) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Sending cancelled. Emails already sent are unaffected.") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "This campaign is not sending.")}
    end
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell flash={@flash} base={@cc_base} active={:campaigns}>
      <div class="flex flex-wrap items-center gap-3 mb-2">
        <h2 class="text-lg font-semibold">{@campaign.name}</h2>
        <.status_badge status={@campaign.status} />
        <div class="grow"></div>
        <button phx-click="refresh" class="btn btn-sm btn-ghost">Refresh</button>
        <button
          :if={@campaign.status == "sending"}
          phx-click="cancel"
          data-confirm="Stop sending? Emails not yet sent will be cancelled."
          class="btn btn-sm btn-error"
          id="cancel-send"
        >
          Cancel sending
        </button>
        <.link navigate={@cc_base <> "/campaigns/" <> @campaign.id} class="btn btn-sm">Campaign</.link>
      </div>
      <div :if={@campaign.note} role="alert" class="alert alert-warning mb-4" id="campaign-note">{@campaign.note}</div>
      <p class="text-sm opacity-70 mb-4">
        Subject: {@campaign.subject} · Approved by {@campaign.approved_by} · Sent by {@campaign.sent_by} · Started {format_time(
          @campaign.send_started_at
        )} · Finished {format_time(@campaign.send_completed_at)}
      </p>

      <div class="stats stats-vertical sm:stats-horizontal shadow w-full mb-2" id="stats">
        <.stat label="Sent" value={@stats.sent} sub={"of #{@stats.total}, #{@stats.queued} queued"} />
        <.stat label="Delivered" value={@stats.delivered} sub={percent(@stats.delivered, @stats.sent)} />
        <.stat label="Opened" value={@stats.opened} sub={percent(@stats.opened, @stats.sent)} />
        <.stat label="Clicked" value={@stats.clicked} sub={percent(@stats.clicked, @stats.sent)} />
      </div>
      <div class="stats stats-vertical sm:stats-horizontal shadow w-full mb-2">
        <.stat label="Bounced" value={@stats.bounced} sub={percent(@stats.bounced, @stats.sent)} />
        <.stat label="Complaints" value={@stats.complained} sub={percent(@stats.complained, @stats.sent)} />
        <.stat label="Unsubscribed" value={@stats.unsubscribed} sub={percent(@stats.unsubscribed, @stats.sent)} />
        <.stat label="Failed / cancelled" value={@stats.failed + @stats.cancelled} sub="" />
      </div>
      <p class="text-xs opacity-60 mb-6">
        Opens are approximate: some mail apps load images automatically (inflating opens) and others block them.
        A click also counts as an open. "Delivered" requires the SES → SNS webhook to be set up.
      </p>

      <form phx-change="filter" class="mb-2">
        <select name="status" class="select select-sm">
          <option value="">All statuses</option>
          <option :for={s <- CustomerContact.Delivery.statuses()} value={s} selected={s == @status_filter}>{s}</option>
        </select>
      </form>

      <div class="overflow-x-auto">
        <table class="table table-xs" id="deliveries">
          <thead>
            <tr>
              <th>Email</th><th>Name</th><th>Status</th><th>Sent</th><th>Opens</th><th>Clicks</th><th>Note</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={d <- @deliveries} id={"delivery-#{d.id}"}>
              <td>{d.email}</td>
              <td>{d.name}</td>
              <td><.status_badge status={d.status} /></td>
              <td>{format_time(d.sent_at)}</td>
              <td>{d.open_count}</td>
              <td>{d.click_count}</td>
              <td class="text-xs">{if d.unsubscribed_at, do: "unsubscribed", else: d.error}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <button :if={length(@deliveries) >= @limit} phx-click="more" class="btn btn-sm btn-ghost mt-2">Show more</button>

      <h3 class="font-semibold mt-8 mb-2">Test sends</h3>
      <p :if={@tests == []} class="text-sm opacity-60">None.</p>
      <table :if={@tests != []} class="table table-xs">
        <tbody>
          <tr :for={d <- @tests}>
            <td>{d.email}</td>
            <td><.status_badge status={d.status} /></td>
            <td>{format_time(d.inserted_at)}</td>
            <td>opens {d.open_count} · clicks {d.click_count}</td>
            <td class="text-xs">{d.error}</td>
          </tr>
        </tbody>
      </table>
    </.shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="stat">
      <div class="stat-title">{@label}</div>
      <div class="stat-value text-2xl">{@value}</div>
      <div class="stat-desc">{@sub}</div>
    </div>
    """
  end
end
