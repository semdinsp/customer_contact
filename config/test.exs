import Config

config :customer_contact, CustomerContact.TestRepo,
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "customer_contact_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :customer_contact, CustomerContact.TestEndpoint,
  url: [host: "example.test", scheme: "https", port: 443],
  # Test-only value, not a real secret.
  secret_key_base: String.duplicate("test-only-secret-key-base-", 4),
  live_view: [signing_salt: "test-only-salt"],
  render_errors: [formats: [html: CustomerContact.TestErrorHTML], layout: false],
  pubsub_server: CustomerContact.TestPubSub,
  server: false

config :customer_contact,
  ecto_repos: [CustomerContact.TestRepo],
  repo: CustomerContact.TestRepo,
  mailer: CustomerContact.TestMailer,
  host: CustomerContact.TestHost,
  endpoint: CustomerContact.TestEndpoint,
  public_path: "/cc",
  sns_topic_arns: ["arn:aws:sns:us-east-1:111111111111:test-ses-events"],
  ses_configuration_set: "test-set"

config :customer_contact, CustomerContact.TestMailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false
config :phoenix, :json_library, Jason
config :logger, level: :warning
