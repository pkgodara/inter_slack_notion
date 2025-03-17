defmodule InterSlackNotion.Services.IntercomService do
  @moduledoc """
  Service for interacting with the Intercom API.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.intercom.io"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"accept", "application/json"},
    {"authorization",
     "Bearer #{Application.get_env(:inter_slack_notion, :intercom)[:access_token]}"}
  ]

  @doc """
  Fetches a conversation from Intercom by its ID.
  Accepts both string and integer IDs.
  """
  def get_conversation(id) when is_binary(id) or is_integer(id) do
    case get("/conversations/#{id}") do
      {:ok, %{status: 200, body: body}} ->
        try do
          case parse_conversation(body) do
            {:ok, conversation} ->
              app_id = Application.get_env(:inter_slack_notion, :intercom)[:app_id]
              url = "https://app.intercom.com/a/apps/#{app_id}/conversations/#{id}"
              {:ok, Map.merge(conversation, %{source: "Intercom", url: url})}

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          e in RuntimeError ->
            {:error, e.message}

          _ ->
            {:error, "Failed to parse conversation data"}
        end

      {:ok, %{status: 401}} ->
        {:error, "Invalid Intercom access token"}

      {:ok, %{status: 404}} ->
        {:error, "Conversation not found"}

      {:error, error} ->
        {:error, "Error fetching conversation: #{inspect(error)}"}
    end
  end

  def get_conversation(nil), do: {:error, "Conversation ID cannot be nil"}
  def get_conversation(_), do: {:error, "Invalid conversation ID format"}

  @doc """
  Sends a message to an Intercom conversation.
  """
  def send_message(conversation_id, message) do
    case me() do
      %{"id" => admin_id} ->
        body = %{
          message_type: "comment",
          body: message,
          type: "admin",
          admin_id: admin_id
        }

        case post("/conversations/#{conversation_id}/reply", body) do
          {:ok, %{status: 200, body: %{"id" => reply_id}}} ->
            {:ok, reply_id}

          {:ok, %{body: body}} ->
            {:error, Map.get(body, "message", "Failed to send message")}

          {:error, error} ->
            {:error, "Error sending message: #{inspect(error)}"}
        end

      {:error, error} ->
        {:error, "Error fetching admin user: #{inspect(error)}"}
    end
  end

  # Private helper functions

  defp me() do
    case get("/me") do
      {:ok, %{status: 200, body: body}} ->
        body

      {:error, error} ->
        {:error, "Error fetching user: #{inspect(error)}"}
    end
  end

  @doc """
  Parses raw conversation data from Intercom API into a structured format.
  """
  def parse_conversation(body) do
    try do
      with conversation_id when not is_nil(conversation_id) <- body["id"],
           conversation_parts when is_list(conversation_parts) <-
             get_in(body, ["conversation_parts", "conversation_parts"]) || [],
           source when not is_nil(source) <- body["source"],
           subject when not is_nil(subject) <- source["subject"] do
        # Handle conversation parts
        messages = parse_conversation_parts(conversation_parts)

        # Add source message only if it contains actual content
        messages =
          case parse_source_message(source) do
            nil -> messages
            source_message -> [source_message | messages]
          end

        admin_participants =
          Enum.filter(messages, fn message ->
            get_in(message, [:author, :type]) == "admin"
          end)
          |> Enum.map(fn message -> message.author end)
          |> Enum.uniq()

        # Convert conversation_id to string to ensure consistent format
        id = to_string(conversation_id)

        conversation = %{
          id: id,
          created_at: body["created_at"],
          updated_at: body["updated_at"],
          source: "Intercom",
          title: subject,
          participants: admin_participants,
          messages: messages
        }

        {:ok, conversation}
      else
        nil -> {:error, "Invalid conversation data"}
        _ -> {:error, "Invalid conversation data"}
      end
    rescue
      e in RuntimeError -> {:error, e.message}
      _ -> {:error, "Failed to parse conversation data"}
    end
  end

  defp parse_source_message(source) when is_map(source) do
    case source do
      %{"body" => body} when not is_nil(body) ->
        %{
          body: body,
          author: parse_author(source["author"]),
          created_at: source["created_at"]
        }

      _ ->
        nil
    end
  end

  defp parse_source_message(_), do: nil

  defp parse_conversation_parts(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn part ->
      # Filter out custom_action parts that don't contain actual messages
      part["part_type"] not in ["custom_action_started", "custom_action_finished"]
    end)
    |> Enum.map(fn part ->
      %{
        body: part["body"],
        author: parse_author(part["author"]),
        created_at: part["created_at"]
      }
    end)
  end

  defp parse_conversation_parts(_), do: []

  defp parse_author(nil), do: nil

  defp parse_author(author) when is_map(author) do
    %{
      name: author["name"],
      email: author["email"],
      type: author["type"]
    }
  end
end
