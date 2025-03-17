defmodule InterSlackNotion.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        InterSlackNotionWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:inter_slack_notion, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: InterSlackNotion.PubSub},
        # Start the Finch HTTP client for sending emails
        {Finch, name: InterSlackNotion.Finch},
        # Start to serve requests, typically the last entry
        InterSlackNotionWeb.Endpoint
      ] ++
        if Application.get_env(:inter_slack_notion, :disable_poller) do
          []
        else
          [InterSlackNotion.Services.NotionPoller]
        end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: InterSlackNotion.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    InterSlackNotionWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
