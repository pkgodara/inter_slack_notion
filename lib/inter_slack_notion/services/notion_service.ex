defmodule InterSlackNotion.Services.NotionService do
  @moduledoc """
  Service for interacting with the Notion API.
  """

  use Tesla

  require Logger

  alias InterSlackNotion.Services.NotionService.{
    PropertyParser,
    DatabaseManager,
    PageManager,
    TicketManager
  }

  plug Tesla.Middleware.BaseUrl, "https://api.notion.com/v1"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"authorization", "Bearer #{Application.get_env(:inter_slack_notion, :notion)[:api_key]}"},
    {"notion-version", "2022-06-28"}
  ]

  @doc """
  Lists all tickets from the Notion database.
  """
  def list_tickets(status \\ "Open") do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]

    body = %{
      filter: %{
        property: "Status",
        status: %{
          equals: status
        }
      },
      sorts: [
        %{
          timestamp: "created_time",
          direction: "descending"
        }
      ]
    }

    case post("/databases/#{database_id}/query", body) do
      {:ok, %{status: 200, body: %{"results" => results}}} ->
        tickets = Enum.map(results, &PropertyParser.parse_ticket/1)
        {:ok, tickets}

      {:ok, %{status: 401}} ->
        {:error, "Invalid Notion API key"}

      {:ok, %{status: 404}} ->
        {:error, "Notion database not found"}

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Notion API error (#{status}): #{message}"}

      {:ok, %{status: status}} ->
        {:error, "Failed to list tickets. Status: #{status}"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to Notion API"}

      {:error, error} ->
        {:error, "Failed to list tickets: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a new ticket in the Notion database.
  """
  def create_ticket(ticket_data) do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]
    ticket_id = TicketManager.generate_random_id()

    properties = %{
      "ID" => PropertyParser.create_rich_text_property(ticket_id),
      "Title" => PropertyParser.create_title_property(ticket_data.title),
      "Intercom Conversations" =>
        PropertyParser.create_conversations_property(ticket_data.intercom_conversations),
      "Slack Channel" => PropertyParser.create_url_property(ticket_data.slack_channel)
    }

    body = %{
      "parent" => %{"database_id" => database_id},
      "icon" => %{"type" => "emoji", "emoji" => "🎫"},
      "properties" => properties,
      "children" => PageManager.create_ticket_children(ticket_data)
    }

    case post("/pages", body) do
      {:ok, %{status: 200, body: page}} ->
        {:ok, PropertyParser.parse_ticket(page)}

      {:ok, resp} ->
        {:error, "Failed to create ticket. Response: #{inspect(resp)}"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to Notion API"}

      {:error, error} ->
        {:error, "Failed to create ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Gets a specific ticket by its ID. Can be either a Notion page UUID or a JMP-NNNN format ticket ID.
  """
  def get_ticket(id) do
    case get("/pages/#{id}") do
      {:ok, %{status: 200, body: page}} ->
        {:ok, PropertyParser.parse_ticket(page)}

      {:ok, %{status: 400}} when is_binary(id) ->
        if String.starts_with?(id, "JMP-") do
          case find_page_id_by_ticket_id(id) do
            {:ok, page_id} -> get_ticket(page_id)
            error -> error
          end
        else
          {:error, "Invalid ticket ID format"}
        end

      {:error, error} ->
        {:error, "Failed to get ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Finds the Notion page UUID for a given ticket ID (JMP-NNNN format).
  """
  def find_page_id_by_ticket_id(ticket_id) when is_binary(ticket_id) do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]

    body = %{
      filter: %{
        property: "ID",
        rich_text: %{
          equals: ticket_id
        }
      }
    }

    case post("/databases/#{database_id}/query", body) do
      {:ok, %{status: 200, body: %{"results" => [page | _]}}} ->
        {:ok, page["id"]}

      {:ok, %{status: 200, body: %{"results" => []}}} ->
        {:error, "Ticket not found: #{ticket_id}"}

      {:error, error} ->
        {:error, "Failed to find ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Updates a ticket's Slack channel URL.
  """
  def update_ticket_slack_channel(ticket_id, slack_channel_id) do
    Logger.info("Updating ticket #{ticket_id} with Slack channel ID: #{slack_channel_id}")

    case Application.get_env(:inter_slack_notion, :slack_team_id) do
      nil ->
        Logger.error("SLACK_TEAM_ID environment variable is not set")
        {:error, "SLACK_TEAM_ID environment variable is not set"}

      team_id ->
        url = "https://app.slack.com/client/#{team_id}/#{slack_channel_id}"
        Logger.info("Setting Slack channel URL to: #{url}")

        case validate_slack_url(url, team_id, slack_channel_id) do
          :ok ->
            properties = %{
              "Slack Channel" => PropertyParser.create_url_property(url)
            }

            case update_ticket(ticket_id, properties) do
              {:ok, updated_ticket} ->
                if updated_ticket.slack_channel == url do
                  Logger.info("Successfully updated ticket with Slack URL: #{url}")
                  {:ok, updated_ticket}
                else
                  Logger.error(
                    "Failed to update Slack URL. Expected: #{url}, Got: #{updated_ticket.slack_channel}"
                  )

                  {:error, "Failed to update Slack channel URL in Notion"}
                end

              {:error, error} ->
                Logger.error("Failed to update ticket with Slack URL: #{inspect(error)}")
                {:error, error}
            end

          {:error, reason} ->
            Logger.error("Invalid Slack URL format: #{reason}")
            {:error, reason}
        end
    end
  end

  @doc """
  Adds a conversation URL to the ticket's Intercom Conversations list.
  """
  def add_conversation_to_ticket(id, conversation) do
    with {:ok, ticket} <- get_ticket(id),
         conversation_url when not is_nil(conversation_url) <- conversation.url do
      current_urls = get_current_urls(ticket.intercom_conversations)
      updated_urls = update_urls_list(current_urls, conversation_url)

      properties = %{
        "Intercom Conversations" => PropertyParser.create_conversations_property(updated_urls)
      }

      case update_ticket(ticket.id, properties) do
        {:ok, updated_ticket} -> {:ok, updated_ticket}
        error -> error
      end
    else
      nil -> {:error, "Invalid conversation URL"}
      error -> error
    end
  end

  @doc """
  Creates a new Notion database with a parent page.
  """
  def create_database(name) do
    with {:ok, parent_id} <- DatabaseManager.find_workspace_root(),
         {:ok, page} <- DatabaseManager.create_parent_page(name, parent_id),
         {:ok, database} <- DatabaseManager.create_database(name, page["id"]) do
      {:ok, database["id"]}
    else
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp update_ticket(page_id, properties) do
    Logger.info("Updating Notion page #{page_id} with properties: #{inspect(properties)}")

    case patch("/pages/#{page_id}", %{"properties" => properties}) do
      {:ok, %{status: 200, body: page}} ->
        updated_ticket = PropertyParser.parse_ticket(page)
        Logger.info("Successfully updated ticket properties: #{inspect(updated_ticket)}")
        {:ok, updated_ticket}

      {:ok, %{status: status, body: %{"object" => "error", "message" => message}}} ->
        Logger.error("Failed to update ticket (#{status}): #{message}")
        {:error, "Failed to update ticket: #{message}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to update ticket (#{status}): #{inspect(body)}")
        {:error, "Failed to update ticket: Status #{status}, #{inspect(body)}"}

      {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
        Logger.error("Connection error updating ticket: #{reason}")
        {:error, "Connection error: #{reason}"}

      {:error, error} ->
        Logger.error("Failed to update ticket: #{inspect(error)}")
        {:error, "Failed to update ticket: #{inspect(error)}"}
    end
  end

  defp get_current_urls(nil), do: []
  defp get_current_urls(url) when is_binary(url), do: [String.trim(url)]
  defp get_current_urls(urls) when is_list(urls), do: Enum.map(urls, &String.trim/1)
  defp get_current_urls(_), do: []

  defp update_urls_list(current_urls, new_url) do
    if new_url in current_urls do
      current_urls
    else
      current_urls ++ [new_url]
    end
  end

  defp validate_slack_url(url, team_id, channel_id) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "app.slack.com", path: "/client/" <> rest} ->
        case String.split(rest, "/") do
          [^team_id, ^channel_id] ->
            Logger.info("URL format verified: team_id=#{team_id}, channel_id=#{channel_id}")
            :ok

          _ ->
            {:error, "Invalid Slack URL format"}
        end

      _ ->
        {:error, "Invalid Slack URL format"}
    end
  end
end
