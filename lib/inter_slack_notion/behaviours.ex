defmodule InterSlackNotion.Behaviours do
  defmodule NotionService do
    @callback list_tickets(String.t()) :: {:ok, list(map())} | {:error, any()}
    @callback create_ticket(map()) :: {:ok, map()} | {:error, any()}
    @callback update_ticket(String.t(), map()) :: {:ok, map()} | {:error, any()}
  end

  defmodule LLMService do
    @callback chat_completion(String.t()) :: {:ok, String.t()} | {:error, any()}
  end

  defmodule TicketManager do
    @callback handle_ticket_done(map()) :: :ok | {:error, any()}
  end
end
