defmodule InterSlackNotion.Services.AIServiceTest do
  use ExUnit.Case, async: true
  alias InterSlackNotion.Services.AIService

  import Tesla.Mock

  @sample_conversation %{
    id: "123",
    title: "API Integration Issue",
    messages: [
      %{
        author: %{name: "John Doe", email: "john@example.com"},
        body: "I'm having issues with the API rate limits",
        created_at: 1_616_733_600
      }
    ],
    url: "https://app.intercom.com/a/apps/abc123/conversations/123",
    participants: [%{name: "Support Agent", email: "agent@company.com"}]
  }

  @existing_tickets [
    %{
      id: "page_123",
      status: "Open",
      title: "Previous API Rate Limit Issue",
      ticket_id: "JMP-000001",
      intercom_conversations: ["https://app.intercom.com/a/apps/abc123/conversations/456"]
    }
  ]

  setup do
    Application.put_env(:inter_slack_notion, :gemini, %{api_key: "test_api_key"})

    mock(fn
      %{
        method: :post,
        url:
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=test_api_key"
      } ->
        json = %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "text" =>
                      Jason.encode!(%{
                        "matches_existing" => false,
                        "suggested_title" => "API: Rate Limit Configuration Issue",
                        "similarity_score" => 60
                      })
                  }
                ]
              }
            }
          ]
        }

        {:ok, %Tesla.Env{status: 200, body: json}}
    end)

    :ok
  end

  describe "analyze_conversation/2" do
    test "creates new ticket when no similar tickets exist" do
      assert {:ok, {:create_new, title}} =
               AIService.analyze_conversation(@sample_conversation, @existing_tickets)

      assert title == "API: Rate Limit Configuration Issue"
    end

    test "suggests existing ticket when similar ticket found" do
      mock(fn
        %{method: :post} ->
          json = %{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" =>
                        Jason.encode!(%{
                          "matches_existing" => true,
                          "ticket_id" => "page_123",
                          "similarity_score" => 85
                        })
                    }
                  ]
                }
              }
            ]
          }

          {:ok, %Tesla.Env{status: 200, body: json}}
      end)

      assert {:ok, {:use_existing, "page_123"}} =
               AIService.analyze_conversation(@sample_conversation, @existing_tickets)
    end

    test "handles invalid conversation data" do
      assert {:error, "Failed to analyze conversation: Invalid conversation data"} =
               AIService.analyze_conversation(nil, @existing_tickets)
    end

    test "handles missing tickets data" do
      assert {:error, "Failed to analyze conversation: Failed to fetch existing tickets"} =
               AIService.analyze_conversation(@sample_conversation, nil)
    end
  end

  describe "generate_conversation_summary/1" do
    test "generates summary for new conversation" do
      conversation = %{
        title: "API Integration Issue",
        messages: [
          %{
            author: %{name: "John Doe", email: "john@example.com"},
            body: "I'm having issues with the API rate limits",
            created_at: 1_616_733_600
          }
        ],
        existing_content: %{
          "current_status" => "Open",
          "main_issue" => "API Integration",
          "steps_taken" => "None",
          "technical_details" => "None"
        }
      }

      mock(fn
        %{method: :post} ->
          json = %{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" =>
                        Jason.encode!(%{
                          "current_status" => "Open",
                          "main_issue" => "API Integration",
                          "steps_taken" => "None",
                          "technical_details" => "None"
                        })
                    }
                  ]
                }
              }
            ]
          }

          {:ok, %Tesla.Env{status: 200, body: json}}
      end)

      summary = %{
        "current_status" => "Open",
        "main_issue" => "API Integration",
        "steps_taken" => "None",
        "technical_details" => "None"
      }

      assert {:ok, ^summary} = AIService.generate_conversation_summary(conversation)
    end

    test "generates summary with existing content" do
      conversation = %{
        title: "API Integration Issue",
        messages: [
          %{
            author: %{name: "John Doe", email: "john@example.com"},
            body: "I'm having issues with the API rate limits",
            created_at: 1_616_733_600
          }
        ],
        existing_content: %{
          "current_status" => "In Progress",
          "main_issue" => "API Rate Limits",
          "steps_taken" => "Initial investigation",
          "technical_details" => "Rate limits: 100 req/min"
        }
      }

      mock(fn
        %{method: :post} ->
          json = %{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" =>
                        Jason.encode!(%{
                          "current_status" => "Open",
                          "main_issue" => "API Integration",
                          "steps_taken" => "None",
                          "technical_details" => "None"
                        })
                    }
                  ]
                }
              }
            ]
          }

          {:ok, %Tesla.Env{status: 200, body: json}}
      end)

      updated_summary = %{
        "current_status" => "Open",
        "main_issue" => "API Integration",
        "steps_taken" => "None",
        "technical_details" => "None"
      }

      assert {:ok, ^updated_summary} = AIService.generate_conversation_summary(conversation)
    end
  end

  describe "error handling" do
    test "handles Gemini API timeout" do
      mock(fn
        %{method: :post} -> {:error, "timeout"}
      end)

      assert {:error, "Failed to analyze conversation: timeout"} =
               AIService.analyze_conversation(@sample_conversation, @existing_tickets)
    end

    test "handles Gemini API rate limit" do
      mock(fn
        %{method: :post} -> {:error, "rate_limit_exceeded"}
      end)

      assert {:error, "Failed to analyze conversation: rate_limit_exceeded"} =
               AIService.analyze_conversation(@sample_conversation, @existing_tickets)
    end

    test "handles invalid JSON response" do
      mock(fn
        %{method: :post} ->
          json = %{
            "candidates" => [
              %{
                "content" => %{
                  "parts" => [
                    %{
                      "text" => "Invalid JSON"
                    }
                  ]
                }
              }
            ]
          }

          {:ok, %Tesla.Env{status: 200, body: json}}
      end)

      assert {:error, "Failed to analyze conversation: Failed to parse AI response"} =
               AIService.analyze_conversation(@sample_conversation, @existing_tickets)
    end
  end
end
