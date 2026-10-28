defmodule CustomerContact.Web.AudienceLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.{Audience, CSV, Log}

  @shown 200
  @max_import_bytes 2_000_000
  @max_import_rows 10_000
  @sample_csv "email,name\r\njane@example.com,Jane Doe\r\n\"lee@example.org\",\"Lee, Sam\"\r\n"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Audience", search: "", host_segments: Audience.host_segments?())
     |> assign(test_form: to_form(Audience.change_test_recipient(), as: :test_recipient))
     |> assign(tag_form: to_form(Audience.change_tag(), as: :tag))
     |> assign(contact_form: to_form(Audience.change_contact(), as: :contact))
     |> assign(import_form: import_form(), import_result: nil)
     |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: @max_import_bytes)
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

  def handle_event("validate_import", %{"import" => params}, socket) do
    {:noreply, assign(socket, import_form: import_form(params))}
  end

  def handle_event("import", %{"import" => params}, socket) do
    tag_id = if params["tag_id"] in [nil, ""] or socket.assigns.host_segments, do: nil, else: params["tag_id"]

    cond do
      socket.assigns.uploads.csv.entries == [] ->
        {:noreply, socket |> assign(import_form: import_form(params)) |> put_flash(:error, "Choose a CSV file first.")}

      params["consent"] != "true" ->
        {:noreply,
         socket
         |> assign(import_form: import_form(params))
         |> put_flash(:error, "Confirm that everyone in the file agreed to receive your emails.")}

      true ->
        case consume_uploaded_entries(socket, :csv, fn %{path: path}, _ -> {:ok, CSV.parse_people(File.read!(path))} end) do
          [parsed] -> {:noreply, socket |> run_import(parsed, tag_id) |> assign(import_form: import_form()) |> load()}
          [] -> {:noreply, put_flash(socket, :error, "That file couldn't be uploaded. Choose it again.")}
        end
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :csv, ref)}

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

  defp run_import(socket, {:error, message}, _tag_id), do: put_flash(socket, :error, message)

  defp run_import(socket, {:ok, rows}, _tag_id) when length(rows) > @max_import_rows,
    do: put_flash(socket, :error, "That file has #{length(rows)} people. Import at most #{@max_import_rows} at a time.")

  defp run_import(socket, {:ok, []}, _tag_id), do: put_flash(socket, :error, "That file has no people in it.")

  defp run_import(socket, {:ok, rows}, tag_id) do
    actor = socket.assigns.cc_actor

    case Audience.import_contacts(rows, actor, tag_id) do
      {:ok, result} ->
        tag = tag_id && Enum.find(socket.assigns.tags, &(&1.id == tag_id))
        Log.info("contacts imported by admin", added: result.added, tagged: result.tagged, by: actor)

        socket
        |> assign(import_result: Map.put(result, :tag, tag && tag.name))
        |> put_flash(:info, import_summary(result))

      {:error, :unknown_tag} ->
        put_flash(socket, :error, "That tag no longer exists. Nothing was imported.")
    end
  end

  defp import_summary(r) do
    "Imported #{r.added} new #{people(r.added)}; #{r.existing} already in the audience." <>
      if(r.invalid == [],
        do: "",
        else: " Skipped #{length(r.invalid)} #{rows(length(r.invalid))} without a valid email."
      )
  end

  defp skipped_lines(lines) do
    n = length(lines)
    shown = lines |> Enum.take(50) |> Enum.join(", ")
    more = if n > 50, do: " and #{n - 50} more", else: ""

    "Skipped #{n} #{rows(n)} without a valid email (#{if n == 1, do: "line", else: "lines"} #{shown}#{more} of the file)."
  end

  defp people(1), do: "person"
  defp people(_), do: "people"
  defp rows(1), do: "row"
  defp rows(_), do: "rows"

  defp import_form(params \\ %{}), do: to_form(Map.take(params, ["tag_id", "consent"]), as: :import)

  defp sample_csv_href, do: "data:text/csv;charset=utf-8," <> URI.encode(@sample_csv, &URI.char_unreserved?/1)

  defp upload_error(:too_large), do: "That file is over 2 MB. Split it into smaller files."
  defp upload_error(:not_accepted), do: "Choose a .csv file."
  defp upload_error(:too_many_files), do: "Choose one file at a time."
  defp upload_error(_), do: "That file couldn't be uploaded."

  defp filtered(recipients, ""), do: Enum.take(recipients, @shown)

  defp filtered(recipients, q) do
    q = String.downcase(q)

    recipients
    |> Enum.filter(fn r -> String.contains?(String.downcase("#{r.name} #{r.email}"), q) end)
    |> Enum.take(@shown)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, max_import_rows: @max_import_rows, sample_csv: @sample_csv)

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
          <li>
            <strong>Import from a CSV file</strong>
            to add many people at once: a spreadsheet saved as CSV with an <em>email</em>
            column and, optionally, a <em>name</em>
            column.<span :if={!@host_segments}> Pick a tag to give everyone in the file that tag.</span>
            Open <em>Guide: preparing your file</em>
            in that block for the details.
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

        <section class="card bg-base-200 lg:col-span-2" id="import">
          <div class="card-body p-4">
            <h2 class="font-semibold">Import people from a CSV file</h2>
            <p class="text-xs opacity-70">
              Adds everyone in the file the same way as <em>Add a person</em>. People already in the audience
              aren't added twice<span :if={!@host_segments}>, but they do get the tag you pick</span>.
            </p>
            <.form
              for={@import_form}
              phx-change="validate_import"
              phx-submit="import"
              class="flex flex-wrap items-end gap-2"
              id="import-form"
            >
              <fieldset class="fieldset">
                <label class="label" for={@uploads.csv.ref}>CSV file</label>
                <.live_file_input upload={@uploads.csv} class="file-input file-input-sm" />
              </fieldset>
              <fieldset :if={!@host_segments} class="fieldset">
                <label class="label" for="import_tag_id">Tag everyone with</label>
                <select id="import_tag_id" name={@import_form[:tag_id].name} class="select select-sm">
                  <option value="">No tag</option>
                  <option :for={t <- @tags} value={t.id} selected={@import_form[:tag_id].value == t.id}>{t.name}</option>
                </select>
              </fieldset>
              <div class="w-full">
                <.input
                  field={@import_form[:consent]}
                  type="checkbox"
                  label="Everyone in this file agreed to receive our emails"
                />
              </div>
              <div :for={entry <- @uploads.csv.entries} class="w-full text-sm flex items-center gap-2">
                <span>{entry.client_name}</span>
                <span :for={err <- upload_errors(@uploads.csv, entry)} class="text-error">{upload_error(err)}</span>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs"
                  aria-label="Remove file"
                >
                  <.icon name="close" />
                </button>
              </div>
              <p :for={err <- upload_errors(@uploads.csv)} class="w-full text-error text-sm">{upload_error(err)}</p>
              <button class="btn btn-sm btn-secondary mb-2" id="import-csv"><.icon name="upload" /> Import</button>
            </.form>

            <div :if={@import_result} class="text-sm" id="import-result">
              <p>
                <strong>{@import_result.added}</strong>
                added, <strong>{@import_result.existing}</strong>
                already in the audience<span :if={@import_result.tag}>,
                  <strong>{@import_result.tagged}</strong> newly tagged <em>{@import_result.tag}</em></span>.
              </p>
              <p :if={@import_result.invalid != []} class="text-warning" id="import-skipped">
                {skipped_lines(@import_result.invalid)}
              </p>
            </div>

            <details class="text-sm mt-2" id="import-guide">
              <summary class="cursor-pointer font-medium">Guide: preparing your file</summary>
              <div class="mt-2 space-y-3">
                <div>
                  <h3 class="font-semibold">What the file needs</h3>
                  <ul class="list-disc pl-5 space-y-1">
                    <li>
                      A <strong>CSV file</strong> (comma-separated values), up to 2 MB and {@max_import_rows} people.
                    </li>
                    <li>
                      A <strong>header row</strong> first, naming the columns. Capitals and the column order don't matter.
                    </li>
                    <li>
                      An <strong>email</strong> column (also accepted: <em>e-mail</em>, <em>email address</em>). Required.
                    </li>
                    <li>
                      A <strong>name</strong>
                      column (or <em>full name</em>), optional. If you have separate <em>first name</em>
                      and <em>last name</em>
                      columns instead, they're joined.
                    </li>
                    <li>Any other columns are ignored, so you can export a whole sheet as it is.</li>
                  </ul>
                </div>
                <div>
                  <h3 class="font-semibold">Example</h3>
                  <pre class="bg-base-100 rounded p-2 text-xs overflow-x-auto">{String.replace(@sample_csv, "\r\n", "\n")}</pre>
                  <p class="text-xs opacity-70">Put a value in double quotes if it contains a comma.</p>
                  <a
                    href={sample_csv_href()}
                    download="audience-import-template.csv"
                    class="link text-xs"
                    id="import-template"
                  >
                    Download this example as a template
                  </a>
                </div>
                <div>
                  <h3 class="font-semibold">Saving a CSV from a spreadsheet</h3>
                  <ul class="list-disc pl-5 space-y-1">
                    <li><strong>Excel:</strong> File → Save As → <em>CSV UTF-8 (Comma delimited)</em>.</li>
                    <li><strong>Google Sheets:</strong> File → Download → <em>Comma-separated values (.csv)</em>.</li>
                    <li>
                      <strong>Numbers:</strong> File → Export To → <em>CSV…</em>, text encoding <em>Unicode (UTF-8)</em>.
                    </li>
                  </ul>
                  <p class="text-xs opacity-70">
                    Files using semicolons instead of commas (some European Excel settings) also work.
                  </p>
                </div>
                <div>
                  <h3 class="font-semibold">What happens when you import</h3>
                  <ul class="list-disc pl-5 space-y-1">
                    <li>
                      Each new address is added to <em>Everyone</em>
                      and <em>Added manually</em>, recorded as added by you with your consent confirmation.
                    </li>
                    <li>
                      Addresses already in the audience (from this app or added earlier) aren't added again.
                      An address listed twice in the file counts once.
                    </li>
                    <li :if={!@host_segments}>
                      With a tag picked, <strong>everyone in the file</strong>
                      gets it, including people already in the audience. Create the tag in <em>Tags</em>
                      below first.
                    </li>
                    <li>Rows with a missing or invalid email are skipped and listed by row number after the import.</li>
                    <li>
                      People on the <strong>suppression list</strong>
                      are added but still won't be emailed. Importing never re-subscribes anyone.
                    </li>
                    <li>
                      Only import people who agreed to receive your emails, e.g. a sign-up sheet. Bought or scraped
                      lists get complaints, and complaints can get your sending suspended.
                    </li>
                    <li>To undo, remove people one by one in the list above.</li>
                  </ul>
                </div>
              </div>
            </details>
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
