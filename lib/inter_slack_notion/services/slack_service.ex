defmodule InterSlackNotion.Services.SlackService do
  @moduledoc """
  Service for interacting with the Slack API.

  This module provides a high-level interface to interact with Slack's Web API,
  handling common operations like channel management, messaging, and user management.
  It includes built-in error handling and rate limiting support.
  """

  use Tesla

  @type slack_id :: String.t()
  @type api_response(type) :: {:ok, type} | {:error, String.t() | {:rate_limited, pos_integer()}}

  # API Endpoints
  @endpoints %{
    create_channel: "/conversations.create",
    set_topic: "/conversations.setTopic",
    list_users: "/users.list",
    invite_user: "/conversations.invite",
    send_message: "/chat.postMessage"
  }

  # Channel name constraints
  @max_channel_name_length 80
  @channel_name_pattern ~r/[^a-z0-9\-_]/

  @doc """
  Creates a Tesla client with the necessary middleware for Slack API communication.
  """
  def client do
    token = Application.get_env(:inter_slack_notion, :slack)[:bot_token]

    middleware = [
      {Tesla.Middleware.BaseUrl, "https://slack.com/api"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]}
    ]

    Tesla.client(middleware)
  end

  @doc """
  Creates a new Slack channel.

  ## Parameters
    * `name` - The name for the new channel. Will be automatically sanitized to
      meet Slack's naming requirements.

  ## Returns
    * `{:ok, channel}` - Channel was created successfully
    * `{:error, reason}` - Channel creation failed
  """
  @spec create_channel(String.t()) :: api_response(map())
  def create_channel(name) do
    body = %{
      name: sanitize_channel_name(name),
      is_private: false
    }

    make_request(:post, @endpoints.create_channel, body, fn
      %{"channel" => channel} -> parse_channel(channel)
    end)
  end

  @doc """
  Sets the topic for a Slack channel.

  ## Parameters
    * `channel_id` - The ID of the channel
    * `topic` - The new topic text

  ## Returns
    * `:ok` - Topic was set successfully
    * `{:error, reason}` - Failed to set topic
  """
  @spec set_channel_topic(slack_id(), String.t()) :: api_response(:ok)
  def set_channel_topic(channel_id, topic) do
    body = %{
      channel: channel_id,
      topic: topic
    }

    make_request(:post, @endpoints.set_topic, body)
  end

  @doc """
  Lists all users in the Slack workspace.

  Excludes deleted users and bots by default.

  ## Returns
    * `{:ok, users}` - List of users retrieved successfully
    * `{:error, reason}` - Failed to retrieve users
  """
  @spec list_users() :: api_response(list(map()))
  def list_users do
    make_request(:get, @endpoints.list_users, nil, fn
      %{"members" => members} -> Enum.map(members, &parse_user/1)
    end)
  end

  @doc """
  Invites a user to a channel.

  ## Parameters
    * `channel_id` - The ID of the channel
    * `user_id` - The ID of the user to invite

  ## Returns
    * `:ok` - User was invited successfully
    * `{:error, reason}` - Failed to invite user
  """
  @spec invite_to_channel(slack_id(), slack_id()) :: api_response(:ok)
  def invite_to_channel(channel_id, user_id) do
    body = %{
      channel: channel_id,
      users: user_id
    }

    make_request(:post, @endpoints.invite_user, body)
  end

  @doc """
  Sends a message to a channel.

  ## Parameters
    * `channel_id` - The ID of the channel
    * `message` - The message text to send

  ## Returns
    * `:ok` - Message was sent successfully
    * `{:error, reason}` - Failed to send message
  """
  @spec send_message(slack_id(), String.t()) :: api_response(:ok)
  def send_message(channel_id, message) do
    body = %{
      channel: channel_id,
      text: message
    }

    make_request(:post, @endpoints.send_message, body)
  end

  # Private helper functions

  @spec make_request(atom(), String.t(), map() | nil, (map() -> term()) | nil) ::
          api_response(term())
  defp make_request(method, endpoint, body, transform_fn \\ nil) do
    client = client()
    request_fn = get_request_function(method)

    response =
      case body do
        nil -> request_fn.(client, endpoint)
        _ -> request_fn.(client, endpoint, body)
      end

    case response do
      {:ok, %{status: 200, body: %{"ok" => true} = resp}} ->
        if transform_fn do
          {:ok, transform_fn.(resp)}
        else
          :ok
        end

      {:ok, %{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, "Slack API error: #{error}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "Unexpected Slack response (status #{status}): #{inspect(body)}"}

      {:error, error} ->
        {:error, "Request failed: #{inspect(error)}"}
    end
  end

  defp get_request_function(:get), do: &Tesla.get/2
  defp get_request_function(:post), do: &Tesla.post/3

  defp get_retry_after(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "retry-after" end)
    |> case do
      {_, value} -> String.to_integer(value)
      nil -> 60
    end
  end

  defp sanitize_channel_name(name) do
    name
    |> String.downcase()
    |> String.replace(@channel_name_pattern, "")
    |> String.slice(0, @max_channel_name_length)
  end

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
