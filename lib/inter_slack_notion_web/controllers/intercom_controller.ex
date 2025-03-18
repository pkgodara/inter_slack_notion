defmodule InterSlackNotionWeb.IntercomController do
  use InterSlackNotionWeb, :controller

  alias InterSlackNotion.Integrations.TicketManager

  require Logger

  @doc """
  Handles incoming webhook requests from Intercom's custom action.
  Accepts either a conversation ID or a full conversation object.
  """
  def create_ticket(conn, %{"conversation" => conversation}) do
    case extract_conversation_id(conversation) do
      {:ok, id} ->
        case TicketManager.handle_intercom_message(id) do
          {:ok, ticket} ->
            json(conn, %{
              status: "success",
              message: "Ticket created/updated successfully",
              ticket: %{
                id: ticket.id,
                title: ticket.title,
                ticket_id: ticket.ticket_id,
                status: ticket.status,
                intercom_conversations: ticket.intercom_conversations,
                slack_channel: ticket.slack_channel,
                url: ticket.url
              }
            })

          {:error, error} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{status: "error", message: "Failed to process ticket: #{error}"})
        end

      {:error, reason} ->
        Logger.error(
          "Failed to extract conversation ID: #{reason}\nPayload: #{inspect(conversation)}"
        )

        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: "Invalid conversation data: #{reason}"})
    end
  end

  def create_ticket(conn, params) do
    Logger.error("Invalid request parameters: #{inspect(params)}")

    conn
    |> put_status(:bad_request)
    |> json(%{status: "error", message: "Invalid request parameters"})
  end

  # Extract conversation ID from either a simple ID or a full conversation object
  defp extract_conversation_id(%{"id" => id}) when is_integer(id), do: {:ok, to_string(id)}
  defp extract_conversation_id(%{"id" => id}) when is_binary(id), do: {:ok, id}

  defp extract_conversation_id(conversation) when is_map(conversation) do
    {:error, "Missing or invalid conversation ID"}
  end

  defp extract_conversation_id(_), do: {:error, "Invalid conversation format"}
end
