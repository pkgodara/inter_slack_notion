defmodule InterSlackNotion.Services.AIService do
  @moduledoc """
  Service for AI-powered analysis and content generation using multi-provider strategy.
  """

  alias InterSlackNotion.Services.GeminiService
  require Logger

  # Order of AI providers to try
  @providers [:gemini]

  @doc """
  Analyzes a conversation and existing tickets to determine if a new ticket should be created.
  Returns either {:create_new, suggested_title} or {:use_existing, ticket_id}
  """
  def analyze_conversation(conversation, existing_tickets) do
    with {:ok, conversation} <- validate_input(conversation, existing_tickets),
         {:ok, ticket_id} <- find_exact_match(conversation, existing_tickets) do
      {:ok, {:use_existing, ticket_id}}
    else
      {:error, :no_match} ->
        analyze_with_ai(conversation, existing_tickets)

      {:error, error} ->
        {:error, "Failed to analyze conversation: #{error}"}
    end
  end

  @doc """
  Generates a summary of the conversation for the ticket.
  """
  def generate_conversation_summary(%{messages: messages} = conversation)
      when is_list(messages) do
    prompt = build_summary_prompt(conversation)

    with {:ok, json_str} <- chat_completion(prompt),
         {:ok, summary} <- parse_summary_response(json_str) do
      {:ok, summary}
    else
      {:error, error} ->
        {:error, "Failed to generate summary: #{error}"}
    end
  end

  # Private helper functions

  defp validate_input(conversation, existing_tickets) do
    case {conversation, existing_tickets} do
      {nil, _} -> {:error, "Invalid conversation data"}
      {_, nil} -> {:error, "Failed to fetch existing tickets"}
      {conv, tickets} when is_map(conv) and is_list(tickets) -> {:ok, conv}
      _ -> {:error, "Invalid data format"}
    end
  end

  defp find_exact_match(%{url: url}, tickets) do
    case Enum.find(tickets, fn ticket ->
           case ticket.intercom_conversations do
             urls when is_list(urls) -> url in urls
             single_url when is_binary(single_url) -> url == single_url
             _ -> false
           end
         end) do
      %{id: page_id, ticket_id: ticket_id} ->
        Logger.info("Found matching ticket #{ticket_id} with page ID #{page_id}")
        {:ok, page_id}

      _ ->
        {:error, :no_match}
    end
  end

  defp analyze_with_ai(conversation, existing_tickets) do
    prompt = build_analysis_prompt(conversation, existing_tickets)

    with {:ok, response} <- chat_completion(prompt),
         {:ok, result} <- parse_analysis_response(response) do
      {:ok, result}
    else
      {:error, error} ->
        {:error, "Failed to analyze conversation: #{error}"}
    end
  end

  defp build_analysis_prompt(conversation, existing_tickets) do
    conversation_text = format_messages(conversation.messages)
    tickets_context = format_tickets(existing_tickets)

    """
    You are a customer support system analyzing a conversation to determine if it matches any existing support tickets.

    Here is the conversation:
    #{conversation_text}

    Here are the existing tickets:
    #{tickets_context}

    Your task:
    1. Analyze if this conversation is related to any existing ticket by comparing:
       - Main issue or topic
       - Technical details or error messages
       - Customer context or background
    2. If it's related to an existing ticket, respond with that ticket's ID
    3. If it's a new issue, suggest a clear and concise title that:
       - Starts with the main category (e.g., "API", "UI", "Account")
       - Describes the specific issue
       - Is under 60 characters
       - Uses title case

    Respond in JSON format:
    {
      "matches_existing": true/false,
      "ticket_id": "ID if matches_existing is true",
      "suggested_title": "Title if matches_existing is false",
      "similarity_score": 0-100
    }
    """
  end

  defp build_summary_prompt(%{title: title, messages: messages}) do
    """
    You are a customer support system. Create a comprehensive summary of this support ticket.

    TICKET TITLE: #{title}

    NEW MESSAGES:
    #{format_messages(messages)}

    Provide a JSON response with these fields:
    1. current_status: Current state of the issue
    2. main_issue: Core problem being addressed
    3. steps_taken: Actions taken so far
    4. technical_details: Technical context and specifications

    Keep each field concise but informative.
    Format as valid JSON.
    """
  end

  defp build_summary_prompt(%{
         title: title,
         messages: messages,
         existing_content: existing_content
       }) do
    """
    You are a customer support system. Create a comprehensive summary of this support ticket.

    TICKET TITLE: #{title}

    EXISTING CONTENT:
    Current Status: #{Map.get(existing_content, "current_status", "N/A")}
    Main Issue: #{Map.get(existing_content, "main_issue", "N/A")}
    Steps Taken: #{Map.get(existing_content, "steps_taken", "N/A")}
    Technical Details: #{Map.get(existing_content, "technical_details", "N/A")}

    NEW MESSAGES:
    #{format_messages(messages)}

    Provide a JSON response with these fields:
    1. current_status: Current state of the issue
    2. main_issue: Core problem being addressed
    3. steps_taken: Actions taken so far
    4. technical_details: Technical context and specifications

    Keep each field concise but informative. Include both existing and new information.
    Format as valid JSON.
    """
  end

  defp parse_analysis_response(response) do
    case parse_json_response(response) do
      {:ok, %{"matches_existing" => true, "ticket_id" => ticket_id, "similarity_score" => score}}
      when score > 80 ->
        {:ok, {:use_existing, ticket_id}}

      {:ok, %{"matches_existing" => false, "suggested_title" => title}}
      when is_binary(title) ->
        {:ok, {:create_new, title}}

      _ ->
        {:error, "Failed to parse AI response"}
    end
  end

  defp parse_summary_response(response) do
    case parse_json_response(response) do
      {:ok,
       %{
         "current_status" => status,
         "main_issue" => issue,
         "steps_taken" => steps,
         "technical_details" => details
       }} ->
        {:ok,
         %{
           "current_status" => status,
           "main_issue" => issue,
           "steps_taken" => steps,
           "technical_details" => details
         }}

      _ ->
        {:error, "Failed to parse AI response"}
    end
  end

  defp format_messages(messages) when is_list(messages) do
    messages
    |> Enum.map(fn msg ->
      author = get_in(msg, [:author, :name]) || "Unknown"

      content =
        msg.body
        |> String.replace(~r/<[^>]*>/, "")
        |> String.trim()

      "#{author}: #{content}"
    end)
    |> Enum.join("\n")
  end

  defp format_tickets(tickets) do
    tickets
    |> Enum.map(fn ticket ->
      """
      Ticket ID: #{ticket.ticket_id}
      Title: #{ticket.title}
      Status: #{ticket.status || "Open"}
      #{if Map.has_key?(ticket, :intercom_conversations) do
        urls = case ticket.intercom_conversations do
          urls when is_list(urls) -> Enum.join(urls, ", ")
          url when is_binary(url) -> url
          _ -> ""
        end
        "Intercom Conversations: #{urls}\n"
      else
        ""
      end}
      #{if Map.has_key?(ticket, :children), do: "Summary: #{ticket.children}\n", else: ""}
      #{if Map.has_key?(ticket, :slack_channel), do: "Slack Channel: #{ticket.slack_channel}\n", else: ""}
      """
    end)
    |> Enum.join("\n\n")
  end

  defp chat_completion(prompt) do
    try_next_provider(prompt, @providers)
  end

  defp try_next_provider(_prompt, []), do: {:error, "All AI services unavailable"}

  defp try_next_provider(prompt, [provider | remaining_providers]) do
    case call_provider(provider, prompt) do
      {:ok, content} ->
        {:ok, content}

      {:error, "rate_limit_exceeded"} ->
        {:error, "rate_limit_exceeded"}

      {:error, error} ->
        case classify_error(error) do
          :recoverable ->
            try_next_provider(prompt, remaining_providers)

          :quota ->
            if remaining_providers == [],
              do: {:error, "AI service quota exceeded"},
              else: try_next_provider(prompt, remaining_providers)

          error_type ->
            {:error, format_error_message(error_type, error)}
        end
    end
  end

  defp call_provider(:gemini, prompt), do: GeminiService.chat_completion(prompt)
  defp call_provider(_, _), do: {:error, "Unsupported AI provider"}

  defp format_error_message(:quota, _), do: "AI service quota exceeded"
  defp format_error_message(:rate_limit, _), do: "rate_limit_exceeded"
  defp format_error_message(:timeout, _), do: "timeout"
  defp format_error_message(_, error), do: "AI service error: #{error}"

  defp parse_json_response(response) do
    case Jason.decode(response) do
      {:ok, %{"content" => content}} ->
        Jason.decode(content)

      {:ok, json} when is_map(json) ->
        {:ok, json}

      {:error, _} ->
        {:error, "Failed to parse JSON response"}
    end
  end

  defp classify_error(error) when is_binary(error) do
    cond do
      String.contains?(String.downcase(error), ["rate limit", "rate_limit", "too many requests"]) ->
        :rate_limit

      String.contains?(String.downcase(error), ["quota", "insufficient balance", "billing"]) ->
        :quota

      String.contains?(String.downcase(error), ["timeout", "connection", "unavailable"]) ->
        :timeout

      true ->
        :unrecoverable
    end
  end
end
