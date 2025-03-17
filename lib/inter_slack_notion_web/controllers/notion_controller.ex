defmodule InterSlackNotionWeb.NotionController do
  use InterSlackNotionWeb, :controller

  alias InterSlackNotion.Integrations.TicketManager

  @done ["Done", "Closed", "Resolved", "Completed"]

  @doc """
  Handles Notion webhook events.
  """
  def webhook(conn, %{"type" => "page_updated"} = params) do
    # Extract the page ID and properties from the webhook payload
    page_id = get_in(params, ["page", "id"])
    properties = get_in(params, ["page", "properties"])

    # Check if the status property was changed to "Done"
    case get_in(properties, ["Status", "status", "name"]) do
      status when status in @done ->
        # Handle the ticket being marked as done
        case TicketManager.handle_ticket_done(page_id) do
          {:ok, :completed} ->
            conn
            |> put_status(:ok)
            |> json(%{status: "success", message: "Ticket marked as done"})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{status: "error", message: "Failed to handle done ticket: #{reason}"})
        end

      _ ->
        # Status was updated but not to "Done", or some other property was updated
        conn
        |> put_status(:ok)
        |> json(%{status: "success", message: "Webhook received"})
    end
  end

  # Handle other webhook event types
  def webhook(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "success", message: "Webhook received"})
  end
end
