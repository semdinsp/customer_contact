defmodule CustomerContact.Web.AudienceLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.Audience

  @shown 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audience", search: "", host_segments: Audience.host_segments?())
     |> assign(test_form: to_form(Audience.change_test_recipient(), as: :test_recipient))
     |> assign(tag_form: to_form(Audience.change_tag(), as: :tag))
     |> load()}
  end

  defp load(socket) do
    socket =
      assign(socket,
        segments: Audience.list_segments(),
        test_recipients: Audience.list_test_recipients(),
        suppressions: Audience.list_suppressions()
      )

    if socket.assigns.host_segments do
      socket
    else
      assign(socket,
        tags: Audience.list_tags(),
        taggings: Audience.taggings_by_ref(),
        recipients: CustomerContact.host().list_recipients()
      )
    end
  end

  @impl true
  def handle_event("add_test", %{"test_recipient" => params}, socket) do
    case Audience.add_test_recipient(params) do
      {:ok, _} ->
        {:noreply,
         socket |> assign(test_form: to_form(Audience.change_test_recipient(), as: :test_recipient)) |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, test_form: to_form(changeset, as: :test_recipient))}
    end
  end

  def handle_event("delete_test", %{"id" => id}, socket) do
    Audience.delete_test_recipient(id)
    {:noreply, load(socket)}
  end

  def handle_event("suppress", %{"email" => email}, socket) do
    case Audience.suppress(email, "manual", "Added by #{socket.assigns.cc_actor}") do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Suppressed #{email}.") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Enter a valid email.")}
    end
  end

  def handle_event("unsuppress", %{"id" => id}, socket) do
    Audience.delete_suppression(id)
    {:noreply, socket |> put_flash(:info, "Removed from the suppression list.") |> load()}
  end

  def handle_event("create_tag", %{"tag" => params}, socket) do
    case Audience.create_tag(params) do
      {:ok, _} -> {:noreply, socket |> assign(tag_form: to_form(Audience.change_tag(), as: :tag)) |> load()}
      {:error, changeset} -> {:noreply, assign(socket, tag_form: to_form(changeset, as: :tag))}
    end
  end

  def handle_event("delete_tag", %{"id" => id}, socket) do
    Audience.delete_tag(id)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_tag", %{"tag" => tag_id, "ref" => ref}, socket) do
    tagged? = MapSet.member?(Map.get(socket.assigns.taggings, ref, MapSet.new()), tag_id)
    if tagged?, do: Audience.untag_recipient(tag_id, ref), else: Audience.tag_recipient(tag_id, ref)
    {:noreply, load(socket)}
  end

  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, search: q)}

  defp filtered(recipients, ""), do: Enum.take(recipients, @shown)

  defp filtered(recipients, q) do
    q = String.downcase(q)

    recipients
    |> Enum.filter(fn r -> String.contains?(String.downcase("#{r.name} #{r.email}"), q) end)
    |> Enum.take(@shown)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell flash={@flash} base={@cc_base} active={:audience}>
      <div class="grid gap-6 lg:grid-cols-2">
        <section class="card bg-base-200">
          <div class="card-body p-4">
            <h2 class="font-semibold">Segments</h2>
            <p :if={@host_segments} class="text-xs opacity-70">Segments come from this app's own tags.</p>
            <ul class="text-sm">
              <li :for={s <- @segments}>{s.name} <span class="opacity-60">({s.count})</span></li>
            </ul>
          </div>
        </section>

        <section class="card bg-base-200" id="test-recipients">
          <div class="card-body p-4">
            <h2 class="font-semibold">Test recipients</h2>
            <p class="text-xs opacity-70">Every test send goes to all of these people.</p>
            <ul class="text-sm">
              <li :for={t <- @test_recipients} class="flex items-center gap-2">
                <span>{t.email}</span><span class="opacity-60">{t.name}</span>
                <button phx-click="delete_test" phx-value-id={t.id} class="btn btn-ghost btn-xs text-error">remove</button>
              </li>
            </ul>
            <.form for={@test_form} phx-submit="add_test" class="flex flex-wrap items-end gap-2" id="test-recipient-form">
              <div class="grow"><.input field={@test_form[:email]} label="Email" type="email" /></div>
              <div class="grow"><.input field={@test_form[:name]} label="Name" /></div>
              <button class="btn btn-sm mb-2">Add</button>
            </.form>
          </div>
        </section>

        <section class="card bg-base-200 lg:col-span-2" id="suppressions">
          <div class="card-body p-4">
            <h2 class="font-semibold">Suppression list</h2>
            <p class="text-xs opacity-70">
              Never emailed by campaigns: unsubscribes, hard bounces, complaints, and manual additions.
              Only remove someone who has asked to be re-subscribed.
            </p>
            <form phx-submit="suppress" class="flex gap-2">
              <input type="email" name="email" placeholder="email@example.com" class="input input-sm" required />
              <button class="btn btn-sm">Suppress</button>
            </form>
            <div class="overflow-x-auto max-h-80">
              <table class="table table-xs">
                <tbody>
                  <tr :for={s <- @suppressions}>
                    <td>{s.email}</td>
                    <td>{s.reason}</td>
                    <td class="text-xs">{s.note}</td>
                    <td>{format_time(s.inserted_at)}</td>
                    <td>
                      <button
                        phx-click="unsuppress"
                        phx-value-id={s.id}
                        data-confirm={"Allow campaigns to email #{s.email} again?"}
                        class="btn btn-ghost btn-xs"
                      >
                        remove
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section :if={!@host_segments} class="card bg-base-200 lg:col-span-2" id="tags">
          <div class="card-body p-4">
            <h2 class="font-semibold">Tags</h2>
            <.form for={@tag_form} phx-submit="create_tag" class="flex flex-wrap items-end gap-2" id="tag-form">
              <div><.input field={@tag_form[:name]} label="New tag" /></div>
              <div class="grow"><.input field={@tag_form[:description]} label="Description" /></div>
              <button class="btn btn-sm mb-2">Create</button>
            </.form>
            <div class="flex flex-wrap gap-2">
              <span :for={t <- @tags} class="badge badge-outline gap-1">
                {t.name}
                <button
                  phx-click="delete_tag"
                  phx-value-id={t.id}
                  data-confirm={"Delete tag #{t.name}? People keep their other tags."}
                  aria-label={"Delete #{t.name}"}
                >
                  ×
                </button>
              </span>
            </div>

            <form phx-change="search" class="mt-4" id="tag-search">
              <input
                type="search"
                name="q"
                value={@search}
                placeholder="Search people"
                class="input input-sm"
                phx-debounce="300"
              />
            </form>
            <div class="overflow-x-auto">
              <table class="table table-xs" id="tag-people">
                <thead>
                  <tr>
                    <th>Name</th><th>Email</th><th :for={t <- @tags}>{t.name}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={r <- filtered(@recipients, @search)}>
                    <td>{r.name}</td>
                    <td>{r.email}</td>
                    <td :for={t <- @tags}>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-xs"
                        checked={MapSet.member?(Map.get(@taggings, to_string(r.ref), MapSet.new()), t.id)}
                        phx-click="toggle_tag"
                        phx-value-tag={t.id}
                        phx-value-ref={r.ref}
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs opacity-60">Showing up to 200 people; search to find others.</p>
          </div>
        </section>
      </div>
    </.shell>
    """
  end
end
