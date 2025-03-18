import Config

# Disable NotionPoller during tests
config :inter_slack_notion, :disable_poller, true

# Configure test environment variables
config :inter_slack_notion,
  slack_team_id: "T12345",
  slack: %{
    bot_token: "test_slack_token"
  },
  notion: %{
    api_key: "test_notion_token",
    database_id: "test_database_id"
  },
  intercom: %{
    access_token: "test_intercom_token",
    app_id: "test_app_id"
  },
  gemini_api_key: "test_gemini_key"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :inter_slack_notion, InterSlackNotionWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "54PteaZWZNpBXd32rjJhS4ugRdU0pZebFY3Obu4HraX0dTlYXrp+jIdySTbu3r4g",
  server: false

# In test we don't send emails
config :inter_slack_notion, InterSlackNotion.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
