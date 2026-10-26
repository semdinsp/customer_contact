defmodule CustomerContact.Web.SentLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.{Campaigns, Delivery}

  @page 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Sent", campaigns: Campaigns.list_campaigns())}
  end

  # Filters live in the URL so a search can be bookmarked or linked to.
  @impl true
  def handle_params(params, _uri, socket) do
    campaign_ids = MapSet.new(socket.assigns.campaigns, & &1.id)

    filters = %{
      "email" => String.slice(params["email"] || "", 0, 254),
      "campaign" => if(params["campaign"] in campaign_ids, do: params["campaign"], else: ""),
      "status" => if(params["status"] in Delivery.statuses(), do: params["status"], else: ""),
      "test" => if(params["test"] == "true", do: "true", else: "")
    }

    limit = if(params["limit"] in ~w(400 800 1600 3200), do: String.to_integer(params["limit"]), else: @page)

    deliveries =
      Campaigns.list_sent(
        email: filters["email"],
        campaign_id: blank_to_nil(filters["campaign"]),
        status: blank_to_nil(filters["status"]),
        test: filters["test"] == "true",
        limit: limit
      )

    {:noreply, assign(socket, filters: filters, limit: limit, deliveries: deliveries)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: path(socket, Map.take(params, ~w(email campaign status test))))}
  end

  def handle_event("more", _params, socket) do
    limit = min(socket.assigns.limit * 2, 3200)
    {:noreply, push_patch(socket, to: path(socket, Map.put(socket.assigns.filters, "limit", limit)))}
  end

  defp path(socket, params) do
    query = params |> Enum.reject(fn {_, v} -> v in [nil, ""] end) |> URI.encode_query()
    socket.assigns.cc_base <> "/sent" <> if(query == "", do: "", else: "?" <> query)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <.shell flash={@flash} base={@cc_base} home={@cc_home} active={:sent}>
      <:help>
        <ul class="list-disc pl-5 space-y-1">
          <li>Every campaign email, newest first: who it went to, which campaign, and what happened to it.</li>
          <li>
            <strong>Search by email</strong> to see everything one person has been sent. Part of an address works too,
            e.g. a domain.
          </li>
          <li>
            Filter by campaign or status, e.g. <em>bounced</em>
            to find bad addresses. Tick <em>Test sends</em>
            to see tests instead of real sends.
          </li>
          <li>Click a campaign name to see the email itself, or <em>Report</em> for its totals.</li>
        </ul>
      </:help>

      <h2 class="text-lg font-semibold mb-4">Sent emails</h2>

      <form phx-change="filter" phx-submit="filter" class="flex flex-wrap items-center gap-2 mb-4" id="sent-filters">
        <input
          type="search"
          name="email"
          value={@filters["email"]}
          placeholder="Search email"
          class="input input-sm"
          phx-debounce="300"
        />
        <select name="campaign" class="select select-sm">
          <option value="">All campaigns</option>
          <option :for={c <- @campaigns} value={c.id} selected={c.id == @filters["campaign"]}>{c.name}</option>
        </select>
        <select name="status" class="select select-sm">
          <option value="">All statuses</option>
          <option :for={s <- Delivery.statuses()} value={s} selected={s == @filters["status"]}>{s}</option>
        </select>
        <label class="label cursor-pointer gap-2 text-sm">
          <input type="checkbox" name="test" value="true" class="checkbox checkbox-sm" checked={@filters["test"] == "true"} />
          Test sends
        </label>
      </form>

      <p :if={@deliveries == []} class="opacity-60" id="no-sent">No emails match.</p>

      <div :if={@deliveries != []} class="overflow-x-auto">
        <table class="table table-xs" id="sent">
          <thead>
            <tr>
              <th>Sent</th><th>Email</th><th>Name</th><th>Campaign</th><th>Status</th><th>Opens</th><th>Clicks</th><th>
                Note
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={d <- @deliveries} id={"sent-#{d.id}"}>
              <td class="whitespace-nowrap">{format_time(d.sent_at || d.inserted_at)}</td>
              <td>{d.email}</td>
              <td>{d.name}</td>
              <td>
                <.link navigate={@cc_base <> "/campaigns/" <> d.campaign_id} class="link link-hover">{d.campaign.name}</.link>
                <.link
                  :if={!d.test}
                  navigate={@cc_base <> "/campaigns/" <> d.campaign_id <> "/report"}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="report" /> Report
                </.link>
              </td>
              <td><.status_badge status={d.status} /></td>
              <td>{d.open_count}</td>
              <td>{d.click_count}</td>
              <td class="text-xs">{if d.unsubscribed_at, do: "unsubscribed", else: d.error}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <button
        :if={length(@deliveries) >= @limit and @limit < 3200}
        phx-click="more"
        class="btn btn-sm btn-ghost mt-2"
        id="sent-more"
      >
        <.icon name="more" /> Show more
      </button>
    </.shell>
    """
  end
end
