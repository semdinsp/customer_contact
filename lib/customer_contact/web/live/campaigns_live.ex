defmodule CustomerContact.Web.CampaignsLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.Campaigns

  @impl true
  def mount(_params, _session, socket) do
    campaigns =
      Enum.map(Campaigns.list_campaigns(), fn c ->
        {c, if(c.status in ~w(sending sent cancelled), do: Campaigns.stats(c.id))}
      end)

    {:ok, assign(socket, campaigns: campaigns, page_title: "Campaigns")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell flash={@flash} base={@cc_base} home={@cc_home} active={:campaigns}>
      <:help>
        <p>Every campaign goes through the same steps, and nothing reaches customers until the last one:</p>
        <ol class="list-decimal pl-5 space-y-1">
          <li>
            <strong>Add yourself as a test recipient</strong>
            on the <.link navigate={@cc_base <> "/audience"} class="link">Audience</.link>
            page (once only).
          </li>
          <li>
            <strong>New campaign:</strong> give it a name and subject, paste the email HTML, choose who it goes to and Save.
          </li>
          <li><strong>Send a test</strong> and check it in your inbox: wording, links, images and the unsubscribe link.</li>
          <li><strong>Approve</strong> by typing the number of recipients shown.</li>
          <li>
            <strong>Send.</strong> The report shows deliveries, opens, clicks, bounces and unsubscribes as they come in.
          </li>
        </ol>
        <p>Changing the email after a test or approval sends it back a step, so customers only ever get what was tested.</p>
      </:help>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Campaigns</h2>
        <.link navigate={@cc_base <> "/campaigns/new"} class="btn btn-primary btn-sm" id="new-campaign">
          <.icon name="plus" /> New campaign
        </.link>
      </div>

      <p :if={@campaigns == []} class="opacity-60">No campaigns yet.</p>

      <div :if={@campaigns != []} class="overflow-x-auto">
        <table class="table table-sm" id="campaigns">
          <thead>
            <tr>
              <th>Name</th>
              <th>Status</th>
              <th>Created</th>
              <th class="text-right">Sent</th>
              <th class="text-right">Opened</th>
              <th class="text-right">Clicked</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{c, stats} <- @campaigns} id={"campaign-#{c.id}"}>
              <td>
                <.link navigate={@cc_base <> "/campaigns/" <> c.id} class="link link-hover font-medium">{c.name}</.link>
                <div class="text-xs opacity-60">{c.subject}</div>
              </td>
              <td><.status_badge status={c.status} /></td>
              <td class="text-xs">{format_time(c.inserted_at)}<br />{c.created_by}</td>
              <td class="text-right">{stats && stats.sent}</td>
              <td class="text-right">{stats && percent(stats.opened, stats.sent)}</td>
              <td class="text-right">{stats && percent(stats.clicked, stats.sent)}</td>
              <td class="text-right">
                <.link :if={stats} navigate={@cc_base <> "/campaigns/" <> c.id <> "/report"} class="btn btn-ghost btn-xs">
                  <.icon name="report" /> Report
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.shell>
    """
  end
end
