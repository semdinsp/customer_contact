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
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold">Campaigns</h2>
        <.link navigate={@cc_base <> "/campaigns/new"} class="btn btn-primary btn-sm" id="new-campaign">
          New campaign
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
                  Report
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
