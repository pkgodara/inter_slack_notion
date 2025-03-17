defmodule InterSlackNotion.Services.DeepseekService do
  @moduledoc """
  Service for AI-powered analysis and content generation using DeepSeek's API.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.deepseek.com/v1"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"authorization", "Bearer #{Application.get_env(:inter_slack_notion, :deepseek)[:api_key]}"}
  ]

  @rate_limit_error "rate_limit_exceeded"
  @quota_error "insufficient_quota"
  @model_error "model_not_found"

  @doc """
  Makes a chat completion request to DeepSeek API.
  """
  def chat_completion(prompt) do
    # Add explicit JSON format instruction
    formatted_prompt = """
    #{prompt}

    IMPORTANT: You must respond in valid JSON format.
    Do not include any explanations or text outside of the JSON structure.
    If the prompt asks for specific JSON fields, include only those fields.
    If no specific format is requested, wrap your response in a simple {"content": "your response"} structure.
    """

    body = %{
      model: "deepseek-reasoner",
      messages: [
        %{
          role: "system",
          content:
            "You are a helpful AI assistant analyzing customer support conversations. Always respond in valid JSON format without any additional text or explanations."
        },
        %{
          role: "user",
          content: formatted_prompt
        }
      ],
      temperature: 0
    }

    case post("/chat/completions", body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: 429, body: %{"error" => %{"code" => @rate_limit_error}}}} ->
        {:error, "DeepSeek rate limit exceeded. Please try again later."}

      {:ok, %{body: %{"error" => %{"code" => @quota_error}}}} ->
        {:error, "DeepSeek API quota exceeded. Please check your billing details."}

      {:ok, %{body: %{"error" => %{"code" => @model_error}}}} ->
        {:error, "DeepSeek model not available. Please check your API access."}

      {:ok, %{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, "DeepSeek API error (#{status}): #{message}"}

      {:error, %Tesla.Error{reason: :timeout}} ->
        {:error, "DeepSeek API request timed out"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to DeepSeek API"}

      {:error, error} ->
        {:error, "DeepSeek API error: #{inspect(error)}"}
    end
  end
end
