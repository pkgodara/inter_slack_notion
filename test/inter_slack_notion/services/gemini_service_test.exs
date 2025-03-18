defmodule InterSlackNotion.Services.GeminiServiceTest do
  use ExUnit.Case, async: true
  import Tesla.Mock
  alias InterSlackNotion.Services.GeminiService

  @test_api_key "test_api_key"
  @sample_prompt "What is the meaning of life?"

  setup do
    Application.put_env(:inter_slack_notion, :gemini, %{api_key: @test_api_key})

    mock(fn
      %{
        method: :post,
        url:
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
              _
      } ->
        case @sample_prompt do
          "What is the meaning of life?" ->
            json(%{
              "candidates" => [
                %{
                  "content" => %{
                    "parts" => [
                      %{
                        "text" => "{\"content\": \"42\"}"
                      }
                    ]
                  }
                }
              ]
            })
        end
    end)

    :ok
  end

  describe "chat_completion/1" do
    test "successfully gets a response" do
      assert {:ok, "{\"content\": \"42\"}"} = GeminiService.chat_completion(@sample_prompt)
    end

    test "handles non-JSON responses" do
      mock(fn
        %{
          method: :post,
          url:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
                _
        } ->
          json(%{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" => "This is a plain text response"
                    }
                  ]
                }
              }
            ]
          })
      end)

      assert {:ok, "{\"content\": \"This is a plain text response\"}"} =
               GeminiService.chat_completion(@sample_prompt)
    end

    test "handles markdown code blocks" do
      mock(fn
        %{
          method: :post,
          url:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
                _
        } ->
          json(%{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" => "```elixir\ndef hello do\n  :world\nend\n```"
                    }
                  ]
                }
              }
            ]
          })
      end)

      expected_response = "{\"content\": \"def hello do\\n  :world\\nend\"}"
      assert {:ok, ^expected_response} = GeminiService.chat_completion(@sample_prompt)
    end

    test "handles API errors" do
      mock(fn
        %{
          method: :post,
          url:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
                _
        } ->
          json(%{"error" => %{"message" => "Invalid API key"}}, status: 401)
      end)

      assert {:error,
              "Gemini API error (401): %{\"error\" => %{\"message\" => \"Invalid API key\"}}"} =
               GeminiService.chat_completion(@sample_prompt)
    end

    test "handles rate limit errors" do
      mock(fn
        %{
          method: :post,
          url:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
                _
        } ->
          json(%{}, status: 429)
      end)

      assert {:error, "rate_limit_exceeded"} = GeminiService.chat_completion(@sample_prompt)
    end

    test "handles quota exceeded errors" do
      mock(fn
        %{
          method: :post,
          url:
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent" <>
                _
        } ->
          json(%{}, status: 403)
      end)

      assert {:error, "quota_exceeded"} = GeminiService.chat_completion(@sample_prompt)
    end
  end
end
