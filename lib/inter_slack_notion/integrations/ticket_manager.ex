defmodule InterSlackNotion.Integrations.TicketManager do
  @moduledoc """
  Manages ticket lifecycle and integrations between services.
  """

  @behaviour InterSlackNotion.Behaviours.TicketManager

  require Logger

  alias InterSlackNotion.Services.{
    IntercomService,
    SlackService,
    NotionService,
    AIService
  }

  @doc """
  Creates or updates a ticket based on an Intercom conversation.
  """
  def handle_intercom_message(conversation_id) do
    with {:ok, conversation} <- IntercomService.get_conversation(conversation_id),
         {:ok, existing_tickets} <- NotionService.list_tickets(),
         {:ok, ai_decision} <- AIService.analyze_conversation(conversation, existing_tickets) do
      case ai_decision do
        {:create_new, suggested_title} ->
          create_new_ticket(conversation, suggested_title)

        {:use_existing, ticket_id} ->
          update_existing_ticket(conversation, ticket_id)
      end
    else
      # Generic errors
      {:error, error} when is_binary(error) ->
        {:error, error}

      {:error, error} ->
        {:error, "Failed to process ticket: #{inspect(error)}"}
    end
  end

  defp create_new_ticket(conversation, suggested_title) do
    with {:ok, notion_ticket} <- create_notion_ticket(conversation, suggested_title),
         {:ok, slack_channel} <- create_slack_channel(notion_ticket, conversation),
         {:ok, updated_ticket} <-
           NotionService.update_ticket_slack_channel(notion_ticket.id, slack_channel.id) do
      # Sync participants in background to not block the response
      Task.start(fn -> sync_participants(conversation, slack_channel.id) end)
      {:ok, updated_ticket}
    else
      {:error, error} ->
        {:error, "Failed to create ticket: #{error}"}
    end
  end

  defp update_existing_ticket(conversation, ticket_id) do
    with {:ok, ticket} <- NotionService.get_ticket(ticket_id),
         {:ok, updated_ticket} <-
           NotionService.add_conversation_to_ticket(ticket_id, conversation),
         channel_id <- extract_channel_id(ticket.slack_channel),
         {:ok, _} <- sync_participants(conversation, channel_id) do
      {:ok, updated_ticket}
    end
  end

  defp extract_channel_id(url) when is_binary(url) do
    # Extract channel ID from Slack channel URL
    # Format: https://app.slack.com/client/{TEAM_ID}/{CHANNEL_ID}
    case Regex.run(~r|/client/[^/]+/([^/]+)|, url) do
      [_, channel_id] -> channel_id
      _ -> nil
    end
  end

  defp extract_channel_id(_), do: nil

  defp create_notion_ticket(conversation, title) do
    with {:ok, summary} <- AIService.generate_conversation_summary(conversation) do
      ticket_data = %{
        title: title,
        intercom_conversations: [conversation.url],
        children: summary,
        # Will be updated after Slack channel creation
        slack_channel: nil
      }

      NotionService.create_ticket(ticket_data)
    end
  end

  defp create_slack_channel(notion_ticket, _conversation) do
    channel_name = generate_channel_name(notion_ticket)
    Logger.info("Creating Slack channel with name: #{channel_name}")

    with {:ok, channel} <- SlackService.create_channel(channel_name),
         :ok <- SlackService.set_channel_topic(channel.id, notion_ticket.url) do
      Logger.info("Created Slack channel: #{inspect(channel)}")
      {:ok, channel}
    else
      {:error, error} ->
        Logger.error("Failed to create Slack channel: #{inspect(error)}")
        {:error, error}
    end
  end

  defp sync_participants(conversation, slack_channel_id, retry_count \\ 0) do
    if retry_count >= 3 do
      Logger.warning("Failed to sync participants after 3 retries due to rate limits")
      {:error, :rate_limit_exceeded}
    else
      case SlackService.list_users() do
        {:ok, slack_users} ->
          matched_users =
            match_users(conversation.participants, slack_users)

          Enum.each(matched_users, fn slack_user_id ->
            SlackService.invite_to_channel(slack_channel_id, slack_user_id)
          end)

          {:ok, matched_users}

        {:error, {:rate_limited, retry_after}} ->
          Logger.info("Rate limited by Slack API, retrying after #{retry_after} seconds")
          Process.sleep(retry_after * 1000)
          sync_participants(conversation, slack_channel_id, retry_count + 1)

        {:error, error} ->
          Logger.error("Failed to sync participants: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  defp match_users(intercom_users, slack_users) do
    Enum.flat_map(intercom_users, fn intercom_user ->
      find_matching_slack_user(intercom_user, slack_users)
    end)
  end

  defp find_matching_slack_user(%{email: email, name: name}, slack_users) do
    # First try matching by email
    case Enum.find(slack_users, &(&1.email == email)) do
      nil ->
        # If no email match, try matching by name using Jaro distance
        find_by_name_similarity(%{name: name}, slack_users)

      slack_user ->
        [slack_user.id]
    end
  end

  defp find_by_name_similarity(%{name: name}, slack_users) do
    threshold = 0.8

    slack_users
    |> Enum.filter(fn slack_user ->
      distance =
        String.jaro_distance(
          String.downcase(name),
          String.downcase(slack_user.name)
        )

      distance >= threshold
    end)
    |> Enum.map(& &1.id)
  end

  defp generate_channel_name(notion_ticket) do
    # Create title slug by converting title to lowercase and replacing non-alphanumeric chars with hyphens
    slug =
      notion_ticket.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    # Extract the 6-digit number from JMP-NNNNNN format
    number =
      case Regex.run(~r/JMP-(\d{6})/, notion_ticket.ticket_id) do
        [_, num] -> num
        # Fallback if pattern doesn't match
        _ -> "000001"
      end

    "jmp-#{number}-#{slug}"
  end

  @doc """
  Handle a ticket being marked as done/resolved.
  - Notifies the Slack channel
  - Notifies Intercom conversations
  """
  def handle_ticket_done(ticket) do
    Logger.info("Handling resolved ticket: #{ticket.ticket_id}")

    with :ok <- notify_slack_channel(ticket),
         :ok <- notify_intercom_conversations(ticket) do
      Logger.info("Successfully handled resolved ticket #{ticket.ticket_id}")
      {:ok, ticket}
    else
      {:error, error} ->
        Logger.error("Failed to handle resolved ticket #{ticket.ticket_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp notify_slack_channel(ticket) do
    channel_id = extract_channel_id(ticket.slack_channel)
    message = "🎉 This ticket has been marked as done! Thank you for your work!"
    SlackService.send_message(channel_id, message)
  end

  def notify_intercom_conversations(ticket) do
    message =
      "The ticket related to this conversation has been resolved. Thank you for your patience!"

    Enum.each(ticket.intercom_conversations, fn conversation_url ->
      conversation_id = extract_conversation_id(conversation_url)
      IntercomService.send_message(conversation_id, message)
    end)
  end

  defp extract_conversation_id(url) do
    # Extract conversation ID from Intercom conversation URL
    url
    |> URI.parse()
    |> Map.get(:path)
    |> String.split("/")
    |> List.last()
  end
end
