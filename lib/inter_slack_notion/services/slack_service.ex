defmodule InterSlackNotion.Services.SlackService do
  @moduledoc """
  Service for interacting with the Slack API.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://slack.com/api"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"authorization", "Bearer #{Application.get_env(:inter_slack_notion, :slack)[:bot_token]}"}
  ]

  @doc """
  Creates a new Slack channel.
  """
  def create_channel(name) do
    # Ensure channel name follows Slack's conventions
    channel_name =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\-_]/, "")
      # Slack's channel name length limit
      |> String.slice(0, 80)

    body = %{
      name: channel_name,
      is_private: false
    }

    case post("/conversations.create", body) do
      {:ok, %{status: 200, body: %{"ok" => true, "channel" => channel}}} ->
        {:ok, parse_channel(channel)}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:error, error} ->
        {:error, "Failed to create channel: #{inspect(error)}"}
    end
  end

  @doc """
  Sets the topic for a Slack channel.
  """
  def set_channel_topic(channel_id, topic) do
    body = %{
      channel: channel_id,
      topic: topic
    }

    case post("/conversations.setTopic", body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:error, error} ->
        {:error, "Failed to set topic: #{inspect(error)}"}
    end
  end

  @doc """
  Lists all users in the Slack workspace.
  """
  def list_users do
    case get("/users.list") do
      {:ok, %{status: 200, body: %{"ok" => true, "members" => members}}} ->
        {:ok, Enum.map(members, &parse_user/1)}

      {:ok, %{status: 429, headers: headers}} ->
        retry_after =
          headers
          |> Enum.find(fn {key, _} -> String.downcase(key) == "retry-after" end)
          |> case do
            {_, value} -> String.to_integer(value)
            # Default to 60 seconds if no Retry-After header
            nil -> 60
          end

        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "Unexpected Slack response (status #{status}): #{inspect(body)}"}

      {:error, error} ->
        {:error, "Failed to list users: #{inspect(error)}"}
    end
  end

  @doc """
  Invites a user to a channel.
  """
  def invite_to_channel(channel_id, user_id) do
    body = %{
      channel: channel_id,
      users: user_id
    }

    case post("/conversations.invite", body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:error, error} ->
        {:error, "Failed to invite user: #{inspect(error)}"}
    end
  end

  @doc """
  Sends a message to a channel.
  """
  def send_message(channel_id, message) do
    body = %{
      channel: channel_id,
      text: message
    }

    case post("/chat.postMessage", body) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:error, error} ->
        {:error, "Failed to send message: #{inspect(error)}"}
    end
  end

  # Private helper functions

  defp parse_channel(channel) do
    %{
      id: channel["id"],
      name: channel["name"],
      is_private: channel["is_private"]
    }
  end

  defp parse_user(user) do
    %{
      id: user["id"],
      name: user["real_name"] || user["name"],
      email: user["profile"]["email"],
      is_bot: user["is_bot"],
      deleted: user["deleted"]
    }
  end
end
