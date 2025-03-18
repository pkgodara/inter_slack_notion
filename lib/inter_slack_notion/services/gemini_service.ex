defmodule InterSlackNotion.Services.GeminiService do
  @moduledoc """
  Service for interacting with Google's Gemini API.
  """

  @behaviour InterSlackNotion.Behaviours.LLMService

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://generativelanguage.googleapis.com/v1beta"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Headers, [{"Content-Type", "application/json"}]

  @doc """
  Makes a chat completion request to the Gemini API.
  """
  def chat_completion(prompt) do
    api_key = Application.get_env(:inter_slack_notion, :gemini)[:api_key]
    model = "gemini-1.5-flash"

    # Add explicit JSON format instruction
    formatted_prompt = """
    #{prompt}

    IMPORTANT: You must respond in valid JSON format.
    Do not include any explanations or text outside of the JSON structure.
    If the prompt asks for specific JSON fields, include only those fields.
    If no specific format is requested, wrap your response in a simple {"content": "your response"} structure.
    """

    body = %{
      contents: [
        %{
          parts: [
            %{
              text: formatted_prompt
            }
          ]
        }
      ],
      safetySettings: [
        %{
          category: "HARM_CATEGORY_DANGEROUS_CONTENT",
          threshold: "BLOCK_NONE"
        }
      ],
      generationConfig: %{
        temperature: 0.0,
        candidateCount: 1,
        maxOutputTokens: 2048,
        topP: 1,
        topK: 1
      }
    }

    case post("/models/#{model}:generateContent?key=#{api_key}", body) do
      {:ok, response} ->
        extract_content(response)

      {:error, %Tesla.Error{reason: :timeout}} ->
        {:error, "timeout"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to Gemini API"}

      {:error, error} ->
        {:error, "Gemini API error: #{inspect(error)}"}
    end
  end

  defp extract_content(%{
         status: 200,
         body: %{"candidates" => [%{"content" => %{"parts" => [%{"text" => content} | _]}} | _]}
       }) do
    # Clean up any markdown code blocks and extra whitespace
    clean_content =
      content
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      # Remove language identifier
      |> String.replace(~r/^\s*elixir\s*/, "")
      |> String.trim()

    # Try to parse the content as JSON first
    case Jason.decode(clean_content) do
      {:ok, json} when is_map(json) ->
        # Return the JSON as is, since it's already in the correct format
        {:ok, clean_content}

      _ ->
        # If not JSON, wrap in content object with consistent formatting
        {:ok, ~s({"content": #{Jason.encode!(clean_content)}})}
    end
  end

  defp extract_content(%{status: 429}) do
    {:error, "rate_limit_exceeded"}
  end

  defp extract_content(%{status: 403}) do
    {:error, "quota_exceeded"}
  end

  defp extract_content(%{status: status, body: body}) do
    {:error, "Gemini API error (#{status}): #{inspect(body)}"}
  end
end
