defmodule CustomerContact do
  @moduledoc """
  Campaign email for Phoenix apps.

  Paste HTML, preview it in the app's branded layout, send a test to a list of
  test recipients, approve, then send to tagged recipients. Delivery, bounces,
  complaints, opens, clicks and unsubscribes are tracked per recipient.

  ## Configuration

      config :customer_contact,
        repo: MyApp.Repo,
        mailer: MyApp.Mailer,
        host: MyApp.CustomerContactHost,   # implements CustomerContact.Host
        endpoint: MyAppWeb.Endpoint,
        public_path: "/cc",                # where CustomerContact.Web.PublicPlug is forwarded
        oban: Oban,                        # Oban instance name
        queue: :customer_contact,
        ses_configuration_set: "my-app-campaigns",
        sns_topic_arns: ["arn:aws:sns:us-east-1:123456789012:my-app-ses-events"]

  See the README for the full integration guide.
  """

  @doc false
  def repo, do: fetch!(:repo)
  @doc false
  def mailer, do: fetch!(:mailer)
  @doc false
  def host, do: fetch!(:host)
  @doc false
  def endpoint, do: fetch!(:endpoint)
  @doc false
  def oban, do: get(:oban, Oban)
  @doc false
  def queue, do: get(:queue, :customer_contact)
  @doc false
  def public_path, do: get(:public_path, "/cc")
  @doc false
  def ses_configuration_set, do: get(:ses_configuration_set)
  @doc false
  def sns_topic_arns, do: get(:sns_topic_arns, [])

  @doc "Absolute URL for a path under the public tracking mount."
  def public_url(path), do: endpoint().url() <> public_path() <> path

  @doc "The host app's brand, merged over defaults."
  def brand do
    Map.merge(
      %{
        name: "",
        logo_url: nil,
        website_url: nil,
        postal_address: nil,
        primary_color: "#1f2937",
        accent_color: "#2563eb",
        background_color: "#f3f4f6",
        reply_to: nil
      },
      host().brand()
    )
  end

  defp fetch!(key) do
    case Application.fetch_env(:customer_contact, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "config :customer_contact, #{inspect(key)} is not set"
    end
  end

  defp get(key, default \\ nil), do: Application.get_env(:customer_contact, key, default)
end
