defmodule InterSlackNotion.Services.NotionPoller do
  @moduledoc """
  GenServer to periodically poll Notion for resolved tickets.
  """
  use GenServer
  require Logger

  alias InterSlackNotion.Services.NotionService
  alias InterSlackNotion.Integrations.TicketManager

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Cache existing resolved tickets on startup
    case NotionService.list_tickets("Resolved") do
      {:ok, tickets} ->
        resolved_tickets = Enum.map(tickets, fn t -> t.id end)
        schedule_next_poll()
        {:ok, %{resolved_tickets: MapSet.new(resolved_tickets)}}

      err ->
        err
    end
  end

  @impl true
  def handle_info(:poll, %{resolved_tickets: cached_tickets} = state) do
    # Fetch current resolved tickets
    current_resolved = fetch_resolved_tickets()

    newly_resolved =
      Enum.filter(current_resolved, fn ticket ->
        not MapSet.member?(cached_tickets, ticket.id)
      end)

    # Handle newly resolved tickets
    newly_resolved
    |> Enum.each(&TicketManager.handle_ticket_done/1)

    resolved_tickets =
      MapSet.union(cached_tickets, newly_resolved |> Enum.map(& &1.id) |> MapSet.new())

    schedule_next_poll()
    {:noreply, %{state | resolved_tickets: resolved_tickets}}
  end

  defp fetch_resolved_tickets do
    case NotionService.list_tickets("Resolved") do
      {:ok, tickets} ->
        tickets

      {:error, error} ->
        Logger.error("Failed to fetch resolved tickets: #{inspect(error)}")
        []
    end
  end

  defp schedule_next_poll do
    poll_interval =
      Application.get_env(:inter_slack_notion, :notion)[:poll_interval_ms] || 300_000

    Process.send_after(self(), :poll, poll_interval)
  end
end
