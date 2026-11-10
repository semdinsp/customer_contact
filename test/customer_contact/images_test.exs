defmodule CustomerContact.ImagesTest do
  use CustomerContact.DataCase, async: false

  alias CustomerContact.{Image, Images}

  # 1x1 PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
       )

  def png, do: @png

  test "stores an image and gives an embeddable URL and img tag" do
    {:ok, image} = Images.create_image(@png, "My Logo (final).PNG", "admin@example.test")

    assert %Image{content_type: "image/png", width: 1, height: 1, filename: "my-logo-final.png", data: nil} = image
    assert image.byte_size == byte_size(@png)
    assert Images.url(image) == "https://example.test/cc/i/#{image.id}/my-logo-final.png"

    tag = Images.img_tag(image)
    assert tag =~ ~s(src="#{Images.url(image)}")
    assert tag =~ ~s(width="1")
    assert tag =~ ~s(alt="")

    assert [%Image{data: nil}] = Images.list_images()
    assert %Image{data: @png} = Images.get_image_with_data(image.id)
  end

  test "the same file uploaded twice is stored once" do
    {:ok, a} = Images.create_image(@png, "a.png", "admin")
    {:ok, b} = Images.create_image(@png, "b.png", "admin")
    assert a.id == b.id
    assert Repo.aggregate(Image, :count) == 1
  end

  test "refuses files that aren't PNG, JPEG, GIF or WebP, whatever their name" do
    assert {:error, :unsupported_type} = Images.create_image("<svg onload=alert(1)>", "x.png", "admin")
    assert {:error, :unsupported_type} = Images.create_image("<html></html>", "x.gif", "admin")
    assert {:error, :empty} = Images.create_image("", "x.png", "admin")
    too_big = @png <> :binary.copy(<<0>>, Images.max_bytes())
    assert {:error, :too_large} = Images.create_image(too_big, "x.png", "admin")
  end

  test "reads type and size from GIF, JPEG and WebP headers" do
    gif = <<"GIF89a", 640::little-16, 480::little-16, 0, 0, 0>>
    assert {:ok, "image/gif", {640, 480}} = Images.detect(gif)

    app0 = <<0xFF, 0xE0, 16::16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>
    sof0 = <<0xFF, 0xC0, 17::16, 8, 300::16, 1200::16, 3>>
    assert {:ok, "image/jpeg", {1200, 300}} = Images.detect(<<0xFF, 0xD8>> <> app0 <> sof0)
    assert {:ok, "image/jpeg", {nil, nil}} = Images.detect(<<0xFF, 0xD8, 0xFF, 0xE0>>)

    vp8x = <<"RIFF", 0::32, "WEBP", "VP8X", 10::little-32, 0::32, 799::little-24, 599::little-24>>
    assert {:ok, "image/webp", {800, 600}} = Images.detect(vp8x)
  end

  test "img tag caps the width at 600px" do
    image = %Image{id: Ecto.UUID.generate(), filename: "wide.png", width: 1800, height: 600}
    assert Images.img_tag(image) =~ ~s(width="600")
  end

  test "an image used by a sent or approved campaign can't be deleted; drafts don't block" do
    {:ok, image} = Images.create_image(@png, "a.png", "admin")
    html = "<p>Hi</p>" <> Images.img_tag(image)

    draft = campaign_fixture(%{html_body: html})
    assert [%{id: id, status: "draft"}] = Images.campaigns_using(image)
    assert id == draft.id

    sent = campaign_fixture(%{name: "Old news", html_body: html})
    Repo.update_all(from(c in CustomerContact.Campaign, where: c.id == ^sent.id), set: [status: "sent"])

    assert {:error, {:in_use, [%{name: "Old news", status: "sent"}]}} = Images.delete_image(image.id, "admin")

    Repo.delete_all(from(c in CustomerContact.Campaign, where: c.id == ^sent.id))
    assert :ok = Images.delete_image(image.id, "admin")
    assert Images.list_images() == []
    assert {:error, :not_found} = Images.delete_image(image.id, "admin")
    assert {:error, :not_found} = Images.delete_image("not-a-uuid", "admin")
  end
end
