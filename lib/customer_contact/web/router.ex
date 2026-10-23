defmodule CustomerContact.Web.Router do
  @moduledoc """
  Router macro for the admin pages.

      import CustomerContact.Web.Router

      scope "/admin" do
        pipe_through [:browser, :require_authenticated_user, :require_admin_user]

        customer_contact_admin "/contact",
          on_mount: [{MyAppWeb.UserAuth, :require_admin}],
          home_path: "/admin"
      end

  `on_mount` MUST include the host's admin check: anyone who can reach these
  pages can email every customer. The plug pipeline guards the first (HTTP)
  request and `on_mount` guards the LiveView socket; both are needed.

  `home_path` is where the home icon in the page header links to, usually the
  app's admin dashboard (default `"/"`).
  """

  defmacro customer_contact_admin(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      on_mount = Keyword.get(opts, :on_mount, [])
      session_name = Keyword.get(opts, :as, :customer_contact_admin)
      home_path = Keyword.get(opts, :home_path, "/")
      base = Phoenix.Router.scoped_path(__MODULE__, path)

      if on_mount == [] do
        raise ArgumentError,
              "customer_contact_admin requires an :on_mount option that enforces admin access"
      end

      scope path, alias: false, as: false do
        live_session session_name,
          on_mount: on_mount ++ [{CustomerContact.Web.Hooks, {:paths, base, home_path}}] do
          live "/", CustomerContact.Web.CampaignsLive, :index
          live "/campaigns/new", CustomerContact.Web.CampaignLive, :new
          live "/campaigns/:id", CustomerContact.Web.CampaignLive, :edit
          live "/campaigns/:id/report", CustomerContact.Web.ReportLive, :show
          live "/audience", CustomerContact.Web.AudienceLive, :index
        end
      end
    end
  end
end
