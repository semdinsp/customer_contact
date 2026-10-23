defmodule CustomerContact.Web.PublicPlug do
  @moduledoc """
  Public endpoints reached from emails and from AWS. Forward to it from the
  host router, outside any CSRF-protected pipeline:

      forward "/cc", CustomerContact.Web.PublicPlug

  Routes (relative to the forward path, which must match `:public_path`):

    * `GET  /o/:token`  - open-tracking pixel
    * `GET  /c/:token`  - click redirect
    * `GET  /u/:token`  - unsubscribe confirmation page
    * `POST /u/:token`  - unsubscribe (also RFC 8058 one-click)
    * `POST /sns`       - Amazon SNS endpoint for SES events
  """

  use Plug.Router

  require Logger

  alias CustomerContact.{SESEvents, SNS, Tracking}

  @pixel Base.decode64!("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
  @max_body 256_000

  plug :match
  plug :dispatch

  get "/o/:token" do
    with {:ok, delivery_id} <- Tracking.verify_open(token) do
      safely(fn -> Tracking.record_open(delivery_id) end)
    end

    conn
    |> put_resp_content_type("image/gif", nil)
    |> put_resp_header("cache-control", "no-store, no-cache, must-revalidate, max-age=0")
    |> send_resp(200, @pixel)
  end

  get "/c/:token" do
    case Tracking.verify_click(token) do
      {:ok, {delivery_id, url}} ->
        safely(fn -> Tracking.record_click(delivery_id, url) end)

        conn
        |> put_resp_header("location", url)
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(302, "")

      :error ->
        page(conn, 404, "Link not found", "This link is invalid or has expired.")
    end
  end

  get "/u/:token" do
    case Tracking.verify_unsubscribe(token) do
      {:ok, {_delivery_id, email}} ->
        # GET only shows a confirmation: link scanners must not unsubscribe people.
        body = """
        <p>Unsubscribe <strong>#{esc(email)}</strong> from #{esc(brand_name())} emails?</p>
        <form method="post" action="">
          <button type="submit" style="padding:10px 20px;font-size:16px;cursor:pointer;">Unsubscribe</button>
        </form>
        """

        page(conn, 200, "Unsubscribe", body, raw: true)

      :error ->
        page(conn, 404, "Link not found", "This unsubscribe link is invalid.")
    end
  end

  post "/u/:token" do
    case Tracking.verify_unsubscribe(token) do
      {:ok, {delivery_id, email}} ->
        Tracking.record_unsubscribe(delivery_id, email)
        page(conn, 200, "Unsubscribed", "#{email} will no longer receive these emails.")

      :error ->
        page(conn, 404, "Link not found", "This unsubscribe link is invalid.")
    end
  end

  post "/sns" do
    with {:ok, msg, conn} <- read_sns(conn),
         :ok <- SNS.verify(msg) do
      handle_sns(msg)
      send_resp(conn, 200, "ok")
    else
      {:error, reason} ->
        Logger.warning("CustomerContact rejected SNS message: #{inspect(reason)}")
        send_resp(conn, 403, "forbidden")

      {:error, reason, conn} ->
        Logger.warning("CustomerContact rejected SNS message: #{inspect(reason)}")
        send_resp(conn, 400, "bad request")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp read_sns(conn) do
    case conn.body_params do
      %{"Type" => _} = params ->
        {:ok, params, conn}

      _ ->
        case Plug.Conn.read_body(conn, length: @max_body) do
          {:ok, body, conn} ->
            case Jason.decode(body) do
              {:ok, %{} = msg} -> {:ok, msg, conn}
              _ -> {:error, :invalid_json, conn}
            end

          {:more, _, conn} ->
            {:error, :too_large, conn}

          {:error, reason} ->
            {:error, reason, conn}
        end
    end
  end

  defp handle_sns(%{"Type" => "SubscriptionConfirmation"} = msg) do
    case SNS.confirm_subscription(msg) do
      :ok -> Logger.info("CustomerContact confirmed SNS subscription to #{msg["TopicArn"]}")
      error -> Logger.warning("CustomerContact could not confirm SNS subscription: #{inspect(error)}")
    end
  end

  defp handle_sns(%{"Type" => "Notification", "Message" => message}) do
    case Jason.decode(message) do
      {:ok, event} -> safely(fn -> SESEvents.handle(event) end)
      _ -> :ok
    end
  end

  defp handle_sns(_), do: :ok

  defp safely(fun) do
    fun.()
  rescue
    e -> Logger.error("CustomerContact tracking error: " <> Exception.message(e))
  end

  defp brand_name do
    CustomerContact.brand().name
  rescue
    _ -> ""
  end

  defp page(conn, status, title, body, opts \\ []) do
    body = if opts[:raw], do: body, else: "<p>#{esc(body)}</p>"

    html = """
    <!DOCTYPE html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex"><title>#{esc(title)}</title></head>
    <body style="font-family:Helvetica,Arial,sans-serif;max-width:520px;margin:64px auto;padding:0 16px;color:#1f2937;line-height:1.5;">
    <h1 style="font-size:22px;">#{esc(title)}</h1>
    #{body}
    </body></html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> send_resp(status, html)
  end

  defp esc(text), do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
