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
          conversation = parse_conversation(body)
          app_id = Application.get_env(:inter_slack_notion, :intercom)[:app_id]
          url = "https://app.intercom.com/a/apps/#{app_id}/conversations/#{id}"
          {:ok, Map.merge(conversation, %{source: "Intercom", url: url})}
        rescue
          e in RuntimeError ->
            {:error, e.message}

          _ ->
            {:error, "Failed to parse conversation data"}
        end

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
    %{
      "type" => "admin",
      "id" => admin_id
    } = me()

    body = %{
      message_type: "comment",
      body: message,
      type: "admin",
      admin_id: admin_id
    }

    case post("/conversations/#{conversation_id}/reply", body) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, err} ->
        {:error, "Failed to send message. Error: #{inspect(err)}"}

      {:error, error} ->
        {:error, "Error sending message: #{inspect(error)}"}
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

  defp parse_conversation(body) do
    with conversation_id when not is_nil(conversation_id) <- body["id"],
         conversation_parts when is_list(conversation_parts) <-
           get_in(body, ["conversation_parts", "conversation_parts"]) || [] do
      conversation_parts = [body["source"] | conversation_parts]

      filtered_parts =
        Enum.filter(conversation_parts, fn part ->
          # Filter out custom_action parts that don't contain actual messages
          part["part_type"] not in ["custom_action_started", "custom_action_finished"]
        end)

      admin_participants =
        Enum.filter(conversation_parts, fn part ->
          part["author"]["type"] == "admin"
        end)
        |> Enum.map(fn part -> parse_author(part["author"]) end)
        |> Enum.uniq()

      # Convert conversation_id to string to ensure consistent format
      id = to_string(conversation_id)
      app_id = System.get_env("INTERCOM_APP_ID")

      %{
        id: id,
        url: "https://app.intercom.com/a/apps/#{app_id}/conversations/#{id}",
        created_at: body["created_at"],
        updated_at: body["updated_at"],
        source: "Intercom",
        title: body["title"],
        participants: admin_participants,
        messages: parse_messages(filtered_parts)
      }
    else
      nil -> raise "Invalid conversation data: missing required fields"
      _ -> raise "Invalid conversation parts format"
    end
  end

  defp parse_messages(conversation_parts) when is_list(conversation_parts) do
    Enum.map(conversation_parts, fn part ->
      with id when not is_nil(id) <- part["id"],
           author when not is_nil(author) <- part["author"] do
        %{
          body: part["body"],
          author: parse_author(author),
          created_at: part["created_at"]
        }
      else
        _ -> raise "Invalid message format: missing required fields"
      end
    end)
  end

  defp parse_author(author) do
    %{
      name: author["name"],
      email: author["email"]
    }
  end
end
