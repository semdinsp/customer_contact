defmodule CustomerContact.Web.ImagesLive do
  @moduledoc false
  use Phoenix.LiveView

  import CustomerContact.Web.Components

  alias CustomerContact.Images

  @accept ~w(.png .jpg .jpeg .gif .webp)
  @max_entries 10
  # Larger than this and the page suggests making the image smaller.
  @large_bytes 1_000_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Images", images: Images.list_images(), large_bytes: @large_bytes)
     |> allow_upload(:image, accept: @accept, max_entries: @max_entries, max_file_size: Images.max_bytes())}
  end

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :image, ref)}

  def handle_event("upload", _params, socket) do
    if socket.assigns.uploads.image.entries == [] do
      {:noreply, put_flash(socket, :error, "Choose an image first.")}
    else
      actor = socket.assigns.cc_actor

      results =
        consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
          {:ok, {entry.client_name, Images.create_image(File.read!(path), entry.client_name, actor)}}
        end)

      failed = for {name, {:error, reason}} <- results, do: "#{name}: #{create_error(reason)}"
      added = length(results) - length(failed)

      socket = assign(socket, images: Images.list_images())

      socket =
        cond do
          failed == [] -> put_flash(socket, :info, uploaded_message(added))
          added == 0 -> put_flash(socket, :error, Enum.join(failed, " "))
          true -> put_flash(socket, :error, uploaded_message(added) <> " Not uploaded: " <> Enum.join(failed, " "))
        end

      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Images.delete_image(id, socket.assigns.cc_actor) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Image deleted.") |> assign(images: Images.list_images())}

      {:error, {:in_use, campaigns}} ->
        names = Enum.map_join(campaigns, ", ", &"\"#{&1.name}\" (#{&1.status})")

        {:noreply,
         put_flash(
           socket,
           :error,
           "Not deleted: it's used by #{names}. Emails from those campaigns would show a broken image."
         )}

      {:error, :not_found} ->
        {:noreply, socket |> put_flash(:error, "That image no longer exists.") |> assign(images: Images.list_images())}
    end
  end

  defp uploaded_message(1), do: "Image uploaded. Copy its HTML below into a campaign."
  defp uploaded_message(n), do: "#{n} images uploaded. Copy their HTML below into a campaign."

  defp create_error(:empty), do: "the file is empty."
  defp create_error(:too_large), do: "it's over #{div(Images.max_bytes(), 1_000_000)} MB."
  defp create_error(:unsupported_type), do: "it isn't a PNG, JPEG, GIF or WebP image."

  defp upload_error(:too_large), do: "Over #{div(Images.max_bytes(), 1_000_000)} MB. Make it smaller first."
  defp upload_error(:not_accepted), do: "Choose a PNG, JPEG, GIF or WebP image."
  defp upload_error(:too_many_files), do: "Choose up to #{@max_entries} images at a time."
  defp upload_error(_), do: "That file couldn't be uploaded."

  defp format_bytes(n) when n >= 1_000_000, do: :erlang.float_to_binary(n / 1_000_000, decimals: 1) <> " MB"
  defp format_bytes(n), do: "#{max(div(n, 1000), 1)} KB"

  @impl true
  def render(assigns) do
    ~H"""
    <.shell flash={@flash} base={@cc_base} home={@cc_home} active={:images}>
      <:help>
        <p>
          Upload pictures here to use them in campaigns. Each image gets a public web address; copy its
          <strong>HTML</strong>
          and paste it into the campaign's email HTML where the picture should appear.
          The campaign preview shows it straight away.
        </p>
        <p>
          PNG, JPEG, GIF and WebP up to {div(Images.max_bytes(), 1_000_000)} MB. Keep email images small (ideally under
          200 KB and about 600 pixels wide, or 1200 for sharp screens): big images load slowly and some inboxes
          clip long emails. Images are shown at up to 600 pixels wide and shrink to fit phones.
        </p>
        <p>
          Change the <code>alt=""</code>
          text to describe the picture: it's read out by screen readers and shown when images are blocked.
        </p>
        <p>
          An image used by a campaign that has been approved or sent can't be deleted, because emails
          already in inboxes would show a broken picture.
        </p>
      </:help>

      <section class="card bg-base-200 mb-6" id="upload">
        <div class="card-body p-4">
          <h2 class="font-semibold">Upload images</h2>
          <form id="upload-form" phx-change="validate_upload" phx-submit="upload" class="flex flex-wrap items-end gap-2">
            <fieldset class="fieldset">
              <label class="label" for={@uploads.image.ref}>
                PNG, JPEG, GIF or WebP, up to {div(Images.max_bytes(), 1_000_000)} MB each
              </label>
              <.live_file_input upload={@uploads.image} class="file-input file-input-sm" />
            </fieldset>
            <button class="btn btn-sm btn-secondary mb-2" id="upload-images"><.icon name="upload" /> Upload</button>
            <div :for={entry <- @uploads.image.entries} class="w-full text-sm flex items-center gap-2">
              <span>{entry.client_name}</span>
              <span :for={err <- upload_errors(@uploads.image, entry)} class="text-error">{upload_error(err)}</span>
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
            <p :for={err <- upload_errors(@uploads.image)} class="w-full text-error text-sm">{upload_error(err)}</p>
          </form>
        </div>
      </section>

      <p :if={@images == []} class="opacity-70" id="no-images">No images yet.</p>

      <div :if={@images != []} class="space-y-4" id="images">
        <div :for={image <- @images} class="card bg-base-100 border border-base-300" id={"image-#{image.id}"}>
          <div class="card-body p-4 flex flex-col sm:flex-row gap-4">
            <a href={Images.url(image)} target="_blank" rel="noopener" class="shrink-0">
              <img
                src={Images.url(image)}
                alt={image.filename}
                class="w-32 h-32 object-contain rounded border border-base-300 bg-base-200"
                loading="lazy"
              />
            </a>
            <div class="grow min-w-0 space-y-2 text-sm">
              <div class="flex flex-wrap items-center gap-2">
                <strong class="break-all">{image.filename}</strong>
                <span :if={image.width} class="opacity-70">{image.width} × {image.height}px</span>
                <span class="opacity-70">{format_bytes(image.byte_size)}</span>
                <span
                  :if={image.byte_size > @large_bytes}
                  class="badge badge-warning badge-sm"
                  title="Large images load slowly in email"
                >
                  large
                </span>
                <div class="grow"></div>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={image.id}
                  data-confirm="Delete this image? Any email that uses it will show a broken picture."
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="trash" /> Delete
                </button>
              </div>
              <p class="text-xs opacity-70">Uploaded by {image.uploaded_by} on {format_time(image.inserted_at)}</p>
              <label class="block">
                <span class="text-xs font-semibold">HTML to paste into a campaign</span>
                <textarea
                  readonly
                  rows="2"
                  class="textarea textarea-sm w-full font-mono text-xs select-all"
                  id={"image-html-#{image.id}"}
                >{Images.img_tag(image)}</textarea>
              </label>
              <label class="block">
                <span class="text-xs font-semibold">Address (URL)</span>
                <input
                  readonly
                  type="text"
                  value={Images.url(image)}
                  class="input input-sm w-full font-mono text-xs select-all"
                  id={"image-url-#{image.id}"}
                />
              </label>
            </div>
          </div>
        </div>
      </div>
    </.shell>
    """
  end
end
