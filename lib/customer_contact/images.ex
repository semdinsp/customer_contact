defmodule CustomerContact.Images do
  @moduledoc """
  Images for campaigns, stored in the app's database (`cc_images`) and served
  publicly from `{public_path}/i/:id/:filename`, so a campaign's HTML can use
  them with `<img src="...">`.

  Only PNG, JPEG, GIF and WebP are accepted, recognised from the file's
  contents rather than its name. SVG is refused: it can carry scripts, and
  most email clients don't show it anyway.

  Uploading the same file twice returns the image already stored.
  """

  import Ecto.Query

  alias CustomerContact.{Campaign, Image, Log}

  @max_bytes 5_000_000
  @email_width 600

  @doc "The largest image accepted, in bytes."
  def max_bytes, do: @max_bytes

  @doc "Every image, newest first, without the image data."
  def list_images, do: repo().all(from i in Image, order_by: [desc: i.inserted_at, desc: i.id])

  @doc "The image with its data, or nil."
  def get_image_with_data(id) do
    if valid_uuid?(id), do: repo().one(from i in Image, where: i.id == ^id, select_merge: %{data: i.data})
  end

  @doc """
  Stores an uploaded image. Returns `{:ok, image}` (the existing image if the
  same file was uploaded before) or `{:error, reason}` where reason is
  `:empty`, `:too_large` or `:unsupported_type`.
  """
  def create_image(data, filename, actor) when is_binary(data) do
    with :ok <- check_size(data),
         {:ok, content_type, {width, height}} <- detect(data) do
      sha = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

      case repo().one(from i in Image, where: i.sha256 == ^sha) do
        %Image{} = existing ->
          {:ok, existing}

        nil ->
          image = %Image{
            filename: safe_filename(filename, content_type),
            content_type: content_type,
            byte_size: byte_size(data),
            width: width,
            height: height,
            sha256: sha,
            data: data,
            uploaded_by: actor
          }

          # The id is generated before the insert, so it's set even when the
          # insert is skipped; re-read by hash to see which row was stored.
          {:ok, image} = repo().insert(image, on_conflict: :nothing, conflict_target: :sha256)
          stored = repo().one!(from i in Image, where: i.sha256 == ^sha)

          if stored.id == image.id do
            Log.info("image uploaded",
              image_id: image.id,
              filename: image.filename,
              bytes: image.byte_size,
              by: actor
            )
          end

          # Lost a race with an identical upload: `stored` is that one.
          {:ok, stored}
      end
    end
  end

  @doc """
  Campaigns whose HTML uses the image, as `[%{id, name, status}]`.
  """
  def campaigns_using(%Image{id: id}) do
    pattern = "%" <> public_path_fragment(id) <> "%"

    repo().all(
      from c in Campaign,
        where: like(c.html_body, ^pattern),
        order_by: [desc: c.inserted_at],
        select: %{id: c.id, name: c.name, status: c.status}
    )
  end

  @doc """
  Deletes an image. Refused with `{:error, {:in_use, campaigns}}` if a
  campaign past the draft stage (approved, sending, sent or cancelled) uses
  it: those emails are in inboxes, or about to be, and would show a broken
  image. `{:error, :not_found}` if there's no such image.
  """
  def delete_image(id, actor) do
    case valid_uuid?(id) && repo().get(Image, id) do
      %Image{} = image ->
        case Enum.reject(campaigns_using(image), &(&1.status == "draft")) do
          [] ->
            repo().delete!(image)
            Log.info("image deleted", image_id: image.id, filename: image.filename, by: actor)
            :ok

          blocking ->
            {:error, {:in_use, blocking}}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc "The image's public URL, for `<img src>`."
  def url(%Image{id: id, filename: filename}), do: CustomerContact.public_url(public_path_fragment(id) <> filename)

  @doc """
  An `<img>` tag ready to paste into a campaign: shown at its natural width up
  to #{@email_width}px, scaling down on narrow screens.
  """
  def img_tag(%Image{} = image) do
    width = if image.width, do: ~s( width="#{min(image.width, @email_width)}"), else: ""

    ~s(<img src="#{url(image)}" alt=""#{width} ) <>
      ~s(style="display:block;max-width:100%;height:auto;border:0;">)
  end

  defp public_path_fragment(id), do: "/i/" <> id <> "/"

  defp check_size(""), do: {:error, :empty}
  defp check_size(data) when byte_size(data) > @max_bytes, do: {:error, :too_large}
  defp check_size(_), do: :ok

  @doc false
  # Recognises the format from the file's first bytes and reads its
  # dimensions. Dimensions are nil when they can't be read.
  def detect(<<0x89, "PNG\r\n", 0x1A, "\n", _::32, "IHDR", w::32, h::32, _::binary>>),
    do: {:ok, "image/png", {w, h}}

  def detect(<<"GIF8", v, "a", w::little-16, h::little-16, _::binary>>) when v in [?7, ?9],
    do: {:ok, "image/gif", {w, h}}

  def detect(<<0xFF, 0xD8, 0xFF, _::binary>> = data), do: {:ok, "image/jpeg", jpeg_size(data, 2)}

  def detect(<<"RIFF", _::32, "WEBP", rest::binary>>), do: {:ok, "image/webp", webp_size(rest)}

  def detect(_), do: {:error, :unsupported_type}

  # Walks the JPEG markers to the start-of-frame, which holds the size.
  defp jpeg_size(data, offset) do
    case data do
      <<_::binary-size(^offset), 0xFF, marker, _len::16, _precision, h::16, w::16, _::binary>>
      when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] ->
        {w, h}

      <<_::binary-size(^offset), 0xFF, 0xFF, _::binary>> ->
        jpeg_size(data, offset + 1)

      <<_::binary-size(^offset), 0xFF, marker, _::binary>> when marker in 0xD0..0xD9 or marker == 0x01 ->
        jpeg_size(data, offset + 2)

      <<_::binary-size(^offset), 0xFF, _marker, len::16, _::binary>> when len >= 2 ->
        jpeg_size(data, offset + 2 + len)

      _ ->
        {nil, nil}
    end
  end

  defp webp_size(<<"VP8 ", _::32, _::24, 0x9D, 0x01, 0x2A, w::little-16, h::little-16, _::binary>>),
    do: {Bitwise.band(w, 0x3FFF), Bitwise.band(h, 0x3FFF)}

  defp webp_size(<<"VP8L", _::32, 0x2F, bits::little-32, _::binary>>),
    do: {Bitwise.band(bits, 0x3FFF) + 1, Bitwise.band(Bitwise.bsr(bits, 14), 0x3FFF) + 1}

  defp webp_size(<<"VP8X", _::32, _::32, w::little-24, h::little-24, _::binary>>), do: {w + 1, h + 1}
  defp webp_size(_), do: {nil, nil}

  @extensions %{"image/png" => ".png", "image/jpeg" => ".jpg", "image/gif" => ".gif", "image/webp" => ".webp"}

  # A URL-safe name ending in the extension for the detected type.
  defp safe_filename(filename, content_type) do
    base =
      (filename || "")
      |> Path.basename()
      |> Path.rootname()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 80)

    if(base == "", do: "image", else: base) <> Map.fetch!(@extensions, content_type)
  end

  defp valid_uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))
  defp repo, do: CustomerContact.repo()
end
