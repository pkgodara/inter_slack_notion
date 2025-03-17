defmodule InterSlackNotion.Services.DeepseekService do
  @moduledoc """
  Service for interacting with the DeepSeek API.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.deepseek.com/v1"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"authorization", "Bearer #{Application.get_env(:inter_slack_notion, :deepseek)[:api_key]}"}
  ]

  @doc """
  Makes a chat completion request to the DeepSeek API.
  """
  def chat_completion(prompt) when is_binary(prompt) do
    body = %{
      model: "deepseek-chat",
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

    case post("/chat/completions", body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: 429}} ->
        {:error, "rate_limit_exceeded"}

      {:ok, %{status: status, body: %{"error" => %{"message" => message}}}} ->
        {:error, "DeepSeek API error (#{status}): #{message}"}

      {:error, %Tesla.Error{reason: :timeout}} ->
        {:error, "timeout"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to DeepSeek API"}

      {:error, error} ->
        {:error, "DeepSeek API error: #{inspect(error)}"}
    end
  end
end
