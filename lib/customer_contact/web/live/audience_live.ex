defmodule CustomerContact.Web.AudienceLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.{Audience, Log}

  @shown 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audience", search: "", host_segments: Audience.host_segments?())
     |> assign(test_form: to_form(Audience.change_test_recipient(), as: :test_recipient))
     |> assign(tag_form: to_form(Audience.change_tag(), as: :tag))
     |> assign(contact_form: to_form(Audience.change_contact(), as: :contact))
     |> load()}
  end

  defp load(socket) do
    suppressions = Audience.list_suppressions()

    socket =
      assign(socket,
        segments: Audience.list_segments(),
        test_recipients: Audience.list_test_recipients(),
        contacts: Audience.list_contacts(),
        suppressions: suppressions,
        suppressed: MapSet.new(suppressions, & &1.email)
      )

    if socket.assigns.host_segments do
      socket
    else
      assign(socket,
        tags: Audience.list_tags(),
        taggings: Audience.taggings_by_ref(),
        recipients: Audience.list_recipients()
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

  def handle_event("add_contact", %{"contact" => params}, socket) do
    case Audience.add_contact(params, socket.assigns.cc_actor) do
      {:ok, contact} ->
        Log.info("contact added by admin", to: Log.mask_email(contact.email), by: socket.assigns.cc_actor)

        note =
          if MapSet.member?(socket.assigns.suppressed, contact.email),
            do: " They're on the suppression list, so campaigns will skip them until they're removed from it.",
            else: ""

        {:noreply,
         socket
         |> put_flash(:info, "Added #{contact.email}." <> note)
         |> assign(contact_form: to_form(Audience.change_contact(), as: :contact))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, contact_form: to_form(changeset, as: :contact))}
    end
  end

  def handle_event("delete_contact", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.contacts, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That person was already removed.")}

      contact ->
        {:ok, _} = Audience.delete_contact(contact.id)
        Log.info("contact removed by admin", to: Log.mask_email(contact.email), by: socket.assigns.cc_actor)
        {:noreply, socket |> put_flash(:info, "Removed #{contact.email} from the audience.") |> load()}
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

  def handle_event("unsubscribe", %{"ref" => ref}, socket) do
    with %{email: email} when is_binary(email) <-
           Enum.find(socket.assigns[:recipients] || [], &(to_string(&1.ref) == ref)),
         {:ok, _} <- Audience.suppress(email, "manual", "Unsubscribed by #{socket.assigns.cc_actor}") do
      Log.info("unsubscribed by admin", to: Log.mask_email(email), by: socket.assigns.cc_actor)
      {:noreply, socket |> put_flash(:info, "Unsubscribed #{email}. Campaigns won't email them.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't unsubscribe that person.")}
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
    <.shell flash={@flash} base={@cc_base} home={@cc_home} active={:audience}>
      <:help>
        <ul class="list-disc pl-5 space-y-1">
          <li>
            <strong>Segments</strong>
            are the groups you can send a campaign to. <em>Everyone</em>
            is all customers with an email address.
          </li>
          <li>
            <strong>Test recipients</strong>
            get every test send. Add yourself and anyone who should check an email before it goes out.
            They don't get the real send unless they are also customers.
          </li>
          <li>
            <strong>Add a person</strong>
            for someone who isn't in this app's own records. Tick the box only if they agreed to receive your emails.
            They join <em>Everyone</em>
            and the <em>Added manually</em>
            segment. <em>Remove</em>
            takes them out again.
          </li>
          <li :if={!@host_segments}>
            <strong>Tags</strong>
            make your own groups: create a tag, then tick people in the table. The tag then appears as a segment.
          </li>
          <li>
            <strong>To stop emailing someone</strong>,
            <span :if={!@host_segments}>click <em>Unsubscribe</em> beside them in the people table, or</span>
            add their address to the <strong>suppression list</strong>. People who unsubscribe themselves, bounce or complain are added automatically.
            Only remove someone from the list if they've asked to be emailed again.
          </li>
        </ul>
      </:help>
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
                <button phx-click="delete_test" phx-value-id={t.id} class="btn btn-ghost btn-xs text-error">
                  <.icon name="trash" /> Remove
                </button>
              </li>
            </ul>
            <.form for={@test_form} phx-submit="add_test" class="flex flex-wrap items-end gap-2" id="test-recipient-form">
              <div class="grow"><.input field={@test_form[:email]} label="Email" type="email" /></div>
              <div class="grow"><.input field={@test_form[:name]} label="Name" /></div>
              <button class="btn btn-sm btn-secondary mb-2"><.icon name="plus" /> Add</button>
            </.form>
          </div>
        </section>

        <section class="card bg-base-200 lg:col-span-2" id="contacts">
          <div class="card-body p-4">
            <h2 class="font-semibold">Add a person</h2>
            <p class="text-xs opacity-70">
              For people who aren't in this app's own records, e.g. someone who signed up at an event.
              They're included in <em>Everyone</em> and in the <em>Added manually</em> segment.
              Only add people who have agreed to receive your emails.
            </p>
            <.form for={@contact_form} phx-submit="add_contact" class="flex flex-wrap items-end gap-2" id="contact-form">
              <div class="grow"><.input field={@contact_form[:email]} label="Email" type="email" /></div>
              <div class="grow"><.input field={@contact_form[:name]} label="Name" /></div>
              <div class="w-full">
                <.input field={@contact_form[:consent]} type="checkbox" label="They agreed to receive our emails" />
              </div>
              <button class="btn btn-sm btn-secondary mb-2" id="add-contact"><.icon name="plus" /> Add person</button>
            </.form>
            <div :if={@contacts != []} class="overflow-x-auto max-h-80">
              <table class="table table-xs" id="contact-list">
                <tbody>
                  <tr :for={c <- @contacts} id={"contact-#{c.id}"}>
                    <td>{c.email}</td>
                    <td>{c.name}</td>
                    <td class="text-xs opacity-70">added by {c.added_by} · {format_time(c.inserted_at)}</td>
                    <td>
                      <span :if={MapSet.member?(@suppressed, c.email)} class="badge badge-ghost badge-sm">unsubscribed</span>
                    </td>
                    <td class="text-right">
                      <button
                        phx-click="delete_contact"
                        phx-value-id={c.id}
                        data-confirm={"Remove #{c.email} from the audience?"}
                        class="btn btn-ghost btn-xs text-error"
                        id={"delete-contact-#{c.id}"}
                      >
                        <.icon name="trash" /> Remove
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
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
              <button class="btn btn-sm btn-secondary"><.icon name="block" /> Suppress</button>
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
                        <.icon name="resubscribe" /> Remove
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
              <button class="btn btn-sm btn-secondary mb-2"><.icon name="tag" /> Create</button>
            </.form>
            <div class="flex flex-wrap gap-2">
              <span :for={t <- @tags} class="badge badge-outline gap-1">
                {t.name}
                <button
                  phx-click="delete_tag"
                  phx-value-id={t.id}
                  data-confirm={"Delete tag #{t.name}? People keep their other tags."}
                  aria-label={"Delete #{t.name}"}
                  class="hover:text-error"
                >
                  <.icon name="close" class="size-3" />
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
                    <th>Name</th><th>Email</th><th :for={t <- @tags}>{t.name}</th><th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={r <- filtered(@recipients, @search)}>
                    <td>{r.name}</td>
                    <td>
                      {r.email}
                      <span :if={String.starts_with?(to_string(r.ref), "manual:")} class="badge badge-ghost badge-xs">
                        added manually
                      </span>
                    </td>
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
                    <td class="text-right">
                      <span
                        :if={r.email && MapSet.member?(@suppressed, Audience.normalize_email(r.email))}
                        class="badge badge-ghost badge-sm"
                      >
                        unsubscribed
                      </span>
                      <button
                        :if={r.email && !MapSet.member?(@suppressed, Audience.normalize_email(r.email))}
                        phx-click="unsubscribe"
                        phx-value-ref={r.ref}
                        data-confirm={"Unsubscribe #{r.email}? Campaigns will stop emailing them."}
                        class="btn btn-ghost btn-xs text-error"
                        id={"unsubscribe-#{r.ref}"}
                      >
                        <.icon name="unsubscribe" /> Unsubscribe
                      </button>
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
