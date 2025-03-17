defmodule InterSlackNotion.Services.NotionServiceTest do
  use ExUnit.Case, async: true
  alias InterSlackNotion.Services.NotionService
  import InterSlackNotion.Test.HTTPMock

  setup do
    Tesla.Mock.mock(fn
      %{method: :post, url: "https://api.notion.com/v1/pages"} = env ->
        handle_request(env)

      %{method: :patch, url: "https://api.notion.com/v1/pages/" <> _} = env ->
        handle_request(env)

      %{method: :get, url: "https://api.notion.com/v1/pages/" <> _} = env ->
        handle_request(env)

      %{method: :post, url: "https://api.notion.com/v1/databases/" <> _} = env ->
        handle_request(env)
    end)

    Application.put_env(:inter_slack_notion, :notion, %{
      api_key: "test_api_key",
      database_id: "test_database_id"
    })

    Application.put_env(:inter_slack_notion, :slack_team_id, "T12345")

    :ok
  end

  defp handle_request(env) do
    case {env.method, env.url} do
      {:post, "https://api.notion.com/v1/pages"} ->
        mock_success(200, %{
          "id" => "page_123",
          "properties" => %{
            "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-000001"}}]},
            "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
            "Intercom Conversations" => %{
              "rich_text" => [
                %{
                  "text" => %{
                    "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                  }
                }
              ]
            },
            "Status" => %{"status" => %{"name" => "Open"}}
          }
        })

      {:patch, "https://api.notion.com/v1/pages/" <> id} ->
        mock_success(200, %{
          "id" => id,
          "properties" => %{
            "Slack Channel" => %{"url" => "https://app.slack.com/client/T12345/C12345"},
            "Intercom Conversations" => %{
              "rich_text" => [
                %{
                  "text" => %{
                    "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                  }
                }
              ]
            }
          }
        })

      {:get, "https://api.notion.com/v1/pages/" <> id} ->
        mock_success(200, %{
          "id" => id,
          "properties" => %{
            "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-000001"}}]},
            "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
            "Status" => %{"status" => %{"name" => "Open"}},
            "Intercom Conversations" => %{
              "rich_text" => [
                %{
                  "text" => %{
                    "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                  }
                }
              ]
            }
          }
        })

      {:post, "https://api.notion.com/v1/databases/" <> _} ->
        mock_success(200, %{
          "results" => [
            %{
              "id" => "page_123",
              "properties" => %{
                "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-000001"}}]}
              }
            }
          ]
        })
    end
  end

  describe "create_ticket/1" do
    test "successfully creates a ticket" do
      ticket_data = %{
        title: "Test Ticket",
        intercom_conversations: ["https://app.intercom.com/a/apps/abc123/conversations/123"],
        children: %{
          "current_status" => "Open",
          "main_issue" => "Test issue",
          "steps_taken" => "Initial creation",
          "technical_details" => "Test details"
        },
        slack_channel: nil
      }

      assert {:ok, ticket} = NotionService.create_ticket(ticket_data)
      assert ticket.ticket_id == "JMP-000001"
      assert ticket.title == "Test Ticket"
    end

    test "handles API errors" do
      ticket_data = %{
        title: "Test Ticket",
        intercom_conversations: [],
        children: %{},
        slack_channel: nil
      }

      Tesla.Mock.mock(fn
        %{method: :post, url: "https://api.notion.com/v1/pages"} ->
          mock_error(401, %{"message" => "Invalid API key"})
      end)

      assert {:error, "Failed to create ticket. Response: " <> _} =
               NotionService.create_ticket(ticket_data)
    end
  end

  describe "update_ticket_slack_channel/2" do
    test "successfully updates Slack channel URL" do
      ticket_id = "page_123"
      channel_id = "C12345"

      assert {:ok, ticket} = NotionService.update_ticket_slack_channel(ticket_id, channel_id)
      assert ticket.slack_channel == "https://app.slack.com/client/T12345/C12345"
    end

    test "validates Slack URL format" do
      Application.delete_env(:inter_slack_notion, :slack_team_id)

      assert {:error, "SLACK_TEAM_ID environment variable is not set"} =
               NotionService.update_ticket_slack_channel("page_123", "C12345")
    end
  end

  describe "add_conversation_to_ticket/2" do
    test "adds new conversation URL" do
      ticket_id = "page_123"
      conversation = %{url: "https://app.intercom.com/a/apps/abc123/conversations/456"}

      Tesla.Mock.mock(fn
        %{method: :get, url: "https://api.notion.com/v1/pages/" <> ^ticket_id} ->
          mock_success(200, %{
            "id" => ticket_id,
            "properties" => %{
              "Intercom Conversations" => %{
                "rich_text" => [
                  %{
                    "text" => %{
                      "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                    }
                  }
                ]
              }
            }
          })

        %{method: :patch, url: "https://api.notion.com/v1/pages/" <> ^ticket_id} ->
          mock_success(200, %{
            "id" => ticket_id,
            "properties" => %{
              "Intercom Conversations" => %{
                "rich_text" => [
                  %{
                    "text" => %{
                      "content" =>
                        "https://app.intercom.com/a/apps/abc123/conversations/123, https://app.intercom.com/a/apps/abc123/conversations/456"
                    }
                  }
                ]
              }
            }
          })
      end)

      assert {:ok, updated_ticket} =
               NotionService.add_conversation_to_ticket(ticket_id, conversation)

      assert length(updated_ticket.intercom_conversations) == 2
    end

    test "handles duplicate conversation URLs" do
      ticket_id = "page_123"
      conversation = %{url: "https://app.intercom.com/a/apps/abc123/conversations/123"}

      assert {:ok, ticket} = NotionService.add_conversation_to_ticket(ticket_id, conversation)
      assert ticket.intercom_conversations == [conversation.url]
    end
  end

  describe "get_ticket/1" do
    test "gets ticket by page ID" do
      ticket_id = "page_123"

      assert {:ok, ticket} = NotionService.get_ticket(ticket_id)
      assert ticket.id == ticket_id
      assert ticket.ticket_id == "JMP-000001"
      assert ticket.title == "Test Ticket"
      assert ticket.status == "Open"
    end

    test "gets ticket by JMP ID" do
      jmp_id = "JMP-000001"

      assert {:ok, ticket} = NotionService.get_ticket(jmp_id)
      assert ticket.ticket_id == jmp_id
      assert ticket.title == "Test Ticket"
    end
  end
end
