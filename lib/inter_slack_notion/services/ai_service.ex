defmodule InterSlackNotion.Services.AIService do
  @moduledoc """
  Service for AI-powered analysis and content generation using multi-provider strategy.
  """

  alias InterSlackNotion.Services.{GeminiService, DeepseekService}
  require Logger

  @rate_limit_error "rate_limit_exceeded"
  @quota_error "insufficient_quota"
  @model_error "model_not_found"

  # Order of AI providers to try
  @providers [:gemini]

  @doc """
  Analyzes a conversation and existing tickets to determine if a new ticket should be created.
  Returns either {:create_new, suggested_title} or {:use_existing, ticket_id}
  """
  @rate_limit_error "rate_limit_exceeded"
  @quota_error "insufficient_quota"
  @model_error "model_not_found"

  def analyze_conversation(conversation, existing_tickets) do
    case {conversation, existing_tickets} do
      {nil, _} ->
        {:error, "Invalid conversation data"}

      {_, nil} ->
        {:error, "Failed to fetch existing tickets"}

      {conversation, existing_tickets} when is_map(conversation) and is_list(existing_tickets) ->
        # First check for exact URL matches
        case find_exact_match(conversation, existing_tickets) do
          {:ok, ticket_id} ->
            {:ok, {:use_existing, ticket_id}}

          _ ->
            # Use AI to analyze content and generate title
            conversation_text = format_messages(conversation.messages)
            tickets_context = format_tickets(existing_tickets)

            prompt = """
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

            case chat_completion(prompt) do
              {:ok, response} ->
                case parse_json_response(response) do
                  {:ok,
                   %{
                     "matches_existing" => true,
                     "ticket_id" => ticket_id,
                     "similarity_score" => score
                   }}
                  when score > 80 ->
                    {:ok, {:use_existing, ticket_id}}

                  {:ok, %{"matches_existing" => false, "suggested_title" => title}}
                  when is_binary(title) ->
                    {:ok, {:create_new, title}}

                  {:ok, %{"content" => content}} when is_binary(content) ->
                    # If we get a simple content response, try to extract a title
                    {:ok, {:create_new, String.slice(content, 0, 60)}}

                  {:error, :invalid_format} ->
                    generate_new_title(conversation)

                  {:error, _reason} ->
                    {:error, "Failed to parse AI response"}
                end

              {:error, error} ->
                {:error, error}
            end
        end

      _ ->
        {:error, "Invalid data format"}
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

  defp generate_new_title(conversation) do
    prompt = """
    Create a clear and concise title for this customer support ticket.
    The title should:
    1. Start with the main category (e.g., "API", "UI", "Account")
    2. Describe the specific issue
    3. Be under 60 characters
    4. Use title case

    Conversation:
    #{format_messages(conversation.messages)}
    """

    case chat_completion(prompt) do
      {:ok, title} -> {:ok, {:create_new, String.trim(title)}}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Generates a summary of the conversation for the ticket.
  """
  def generate_conversation_summary(%{title: title, messages: messages}) when is_list(messages) do
    prompt = """
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

    case chat_completion(prompt) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, summary} -> {:ok, summary}
          {:error, _} -> {:error, "Failed to parse AI response as JSON"}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  def generate_conversation_summary(%{
        title: title,
        messages: messages,
        existing_content: existing_content
      })
      when is_list(messages) do
    prompt = """
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

    case chat_completion(prompt) do
      {:ok, json_str} ->
        case Jason.decode(json_str) do
          {:ok, summary} -> {:ok, summary}
          {:error, _} -> {:error, "Failed to parse AI response as JSON"}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # Private helper functions

  defp format_messages(messages) when is_list(messages) do
    messages
    |> Enum.map(fn msg ->
      author = get_in(msg, [:author, :name]) || "Unknown"

      content =
        msg.body
        # Remove HTML tags
        |> String.replace(~r/<[^>]*>/, "")
        |> String.trim()

      "#{author}: #{content}"
    end)
    |> Enum.join("\n")
  end

  defp chat_completion(prompt) do
    try_next_provider(prompt, @providers)
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

  defp try_next_provider(_prompt, []), do: {:error, "All AI services unavailable"}

  defp try_next_provider(prompt, [provider | remaining_providers]) do
    case call_provider(provider, prompt) do
      {:ok, content} ->
        {:ok, content}

      {:error, error} ->
        case classify_error(error) do
          # For recoverable errors or rate limits, try the next provider
          error_type when error_type in [:recoverable, :rate_limit] ->
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

  defp call_provider(:deepseek, prompt), do: DeepseekService.chat_completion(prompt)
  defp call_provider(:openai, prompt), do: openai_chat_completion(prompt)
  defp call_provider(:gemini, prompt), do: GeminiService.chat_completion(prompt)

  defp format_error_message(:quota, _), do: "AI service quota exceeded"

  defp format_error_message(:rate_limit, _),
    do: "AI service rate limit exceeded - please try again later"

  defp format_error_message(_, error), do: "AI service error: #{error}"

  # Parse and validate JSON response from any AI provider
  defp parse_json_response(response) when is_binary(response) do
    case Jason.decode(response) do
      {:ok, json} when is_map(json) ->
        cond do
          # Check for our expected ticket analysis format
          Map.has_key?(json, "matches_existing") and
              (Map.has_key?(json, "ticket_id") or Map.has_key?(json, "suggested_title")) ->
            {:ok, json}

          # Check for simple content wrapper
          Map.has_key?(json, "content") ->
            {:ok, json}

          # Try to interpret the entire response as content if it's a simple object
          map_size(json) == 1 ->
            {:ok, %{"content" => inspect(json)}}

          true ->
            {:error, :invalid_format}
        end

      {:error, error} ->
        IO.puts("\nJSON parse error:")
        IO.inspect(error)
        {:error, :invalid_json}
    end
  end

  defp parse_json_response(_), do: {:error, :invalid_input}

  # Classify error types to determine if we should try fallback
  defp classify_error(error) when is_binary(error) do
    cond do
      String.contains?(String.downcase(error), ["rate limit", "rate_limit", "too many requests"]) ->
        :rate_limit

      String.contains?(String.downcase(error), ["quota", "insufficient balance", "billing"]) ->
        :quota

      String.contains?(String.downcase(error), ["timeout", "connection", "unavailable"]) ->
        :recoverable

      true ->
        :unrecoverable
    end
  end

  defp classify_error(_), do: :unrecoverable

  defp openai_chat_completion(prompt) do
    # Configure OpenAI client
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"authorization",
          "Bearer #{Application.get_env(:inter_slack_notion, :openai)[:api_key]}"}
       ]}
    ]

    client = Tesla.client(middleware)

    body = %{
      model: "gpt-3.5-turbo",
      messages: [
        %{
          role: "system",
          content: "You are a helpful AI assistant analyzing customer support conversations."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      temperature: 0.7
    }

    case Tesla.post(client, "/chat/completions", body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: 429, body: %{"error" => %{"code" => @rate_limit_error}}}} ->
        {:error, "OpenAI rate limit exceeded"}

      {:ok, %{body: %{"error" => %{"code" => @quota_error}}}} ->
        {:error, "OpenAI API quota exceeded"}

      {:ok, %{body: %{"error" => %{"code" => @model_error}}}} ->
        {:error, "OpenAI model not available"}

      {:ok, %{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, "OpenAI API error (#{status}): #{message}"}

      {:error, %Tesla.Error{reason: :timeout}} ->
        {:error, "OpenAI API request timed out"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to OpenAI API"}

      {:error, error} ->
        {:error, "OpenAI API error: #{inspect(error)}"}
    end
  end
end
