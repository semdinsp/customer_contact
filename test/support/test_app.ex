defmodule CustomerContact.TestRepo do
  use Ecto.Repo, otp_app: :customer_contact, adapter: Ecto.Adapters.Postgres
end

defmodule CustomerContact.TestMailer do
  use Swoosh.Mailer, otp_app: :customer_contact
end

defmodule CustomerContact.TestHost do
  @behaviour CustomerContact.Host
  alias CustomerContact.Recipient

  @impl true
  def brand do
    %{
      name: "Test Org",
      from: {"Test Org", "news@example.test"},
      postal_address: "1 Test St, Testville",
      website_url: "https://example.test"
    }
  end

  @impl true
  def list_recipients do
    Process.get(:cc_recipients, [
      %Recipient{ref: "1", email: "Alice@Example.com", name: "Alice Smith"},
      %Recipient{ref: "2", email: "bob@example.com", name: "Bob"},
      %Recipient{ref: "3", email: "alice@example.com", name: "Alice duplicate"},
      %Recipient{ref: "4", email: nil, name: "No email"}
    ])
  end
end

defmodule CustomerContact.TestErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule CustomerContact.TestAuth do
  # Stands in for the host's admin on_mount check.
  def on_mount(:require_admin, _params, session, socket) do
    if session["admin"] do
      {:cont, Phoenix.Component.assign(socket, :current_scope, %{user: %{email: "admin@example.test"}})}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end
end

defmodule CustomerContact.TestRouter do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import CustomerContact.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
  end

  scope "/admin" do
    pipe_through :browser
    customer_contact_admin "/contact", on_mount: [{CustomerContact.TestAuth, :require_admin}], home_path: "/admin"
  end

  forward "/cc", CustomerContact.Web.PublicPlug
end

defmodule CustomerContact.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :customer_contact

  @session [store: :cookie, key: "_cc_test", signing_salt: "test-only"]
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]]

  plug Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: Jason
  plug Plug.Session, @session
  plug CustomerContact.TestRouter
end

defmodule CustomerContact.TestMigration do
  use Ecto.Migration
  def up, do: CustomerContact.Migrations.up()
  def down, do: CustomerContact.Migrations.down()
end

defmodule CustomerContact.TestObanMigration do
  use Ecto.Migration
  def up, do: Oban.Migrations.up()
  def down, do: Oban.Migrations.down(version: 1)
end
