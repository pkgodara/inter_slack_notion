defmodule InterSlackNotion.Services.NotionServiceTest do
  use ExUnit.Case, async: true
  import Tesla.Mock
  alias InterSlackNotion.Services.NotionService

  @test_api_key "test_api_key"
  @test_database_id "test_database_id"
  @test_slack_team_id "T12345"

  setup do
    Application.put_env(:inter_slack_notion, :notion, %{
      api_key: @test_api_key,
      database_id: @test_database_id
    })

    Application.put_env(:inter_slack_notion, :slack_team_id, @test_slack_team_id)

    mock(fn
      %{method: :patch, url: "https://api.notion.com/v1/pages/" <> _page_id} = env ->
        case Jason.decode!(env.body) do
          %{"properties" => %{"Slack Channel" => %{"type" => "url", "url" => _}}} ->
            json(%{
              "id" => "page_123",
              "properties" => %{
                "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-123456"}}]},
                "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
                "Status" => %{"select" => %{"name" => "Resolved"}},
                "Intercom Conversations" => %{
                  "type" => "rich_text",
                  "rich_text" => [
                    %{
                      "type" => "text",
                      "text" => %{
                        "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                      }
                    }
                  ]
                },
                "Slack Channel" => %{
                  "type" => "url",
                  "url" => "https://app.slack.com/client/T12345/C12345"
                }
              }
            })

          %{
            "properties" => %{
              "Intercom Conversations" => %{"rich_text" => [%{"text" => %{"content" => _}}]}
            }
          } ->
            json(%{
              "id" => "page_123",
              "properties" => %{
                "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-123456"}}]},
                "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
                "Status" => %{"select" => %{"name" => "Resolved"}},
                "Intercom Conversations" => %{
                  "type" => "rich_text",
                  "rich_text" => [
                    %{
                      "type" => "text",
                      "text" => %{
                        "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                      }
                    }
                  ]
                },
                "Slack Channel" => %{
                  "type" => "url",
                  "url" => "https://app.slack.com/client/T12345/C12345"
                }
              }
            })
        end

      %{method: :get, url: "https://api.notion.com/v1/pages/" <> page_id} ->
        json(%{
          "id" => page_id,
          "properties" => %{
            "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-123456"}}]},
            "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
            "Status" => %{"select" => %{"name" => "Resolved"}},
            "Intercom Conversations" => %{
              "type" => "rich_text",
              "rich_text" => [
                %{
                  "type" => "text",
                  "text" => %{
                    "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                  }
                }
              ]
            },
            "Slack Channel" => %{
              "type" => "url",
              "url" => "https://app.slack.com/client/T12345/C12345"
            }
          }
        })

      %{method: :post, url: "https://api.notion.com/v1/databases/" <> _rest} ->
        json(%{
          "results" => [
            %{
              "id" => "page_123",
              "properties" => %{
                "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-123456"}}]},
                "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
                "Status" => %{"select" => %{"name" => "Resolved"}},
                "Intercom Conversations" => %{
                  "type" => "rich_text",
                  "rich_text" => [
                    %{
                      "type" => "text",
                      "text" => %{
                        "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                      }
                    }
                  ]
                },
                "Slack Channel" => %{
                  "type" => "url",
                  "url" => "https://app.slack.com/client/T12345/C12345"
                }
              }
            }
          ]
        })

      %{method: :post, url: "https://api.notion.com/v1/pages"} = env ->
        case Jason.decode!(env.body) do
          %{"properties" => _} ->
            json(%{
              "id" => "page_123",
              "properties" => %{
                "ID" => %{"rich_text" => [%{"text" => %{"content" => "JMP-123456"}}]},
                "Title" => %{"title" => [%{"text" => %{"content" => "Test Ticket"}}]},
                "Status" => %{"select" => %{"name" => "New"}},
                "Intercom Conversations" => %{
                  "type" => "rich_text",
                  "rich_text" => [
                    %{
                      "type" => "text",
                      "text" => %{
                        "content" => "https://app.intercom.com/a/apps/abc123/conversations/123"
                      }
                    }
                  ]
                },
                "Slack Channel" => %{
                  "type" => "url",
                  "url" => nil
                }
              }
            })

          _ ->
            json(%{"message" => "Invalid API key"}, status: 401)
        end
    end)

    :ok
  end

  describe "list_tickets/1" do
    test "successfully lists resolved tickets" do
      {:ok, tickets} = NotionService.list_tickets("Resolved")
      assert length(tickets) > 0
      assert hd(tickets).id == "page_123"
      assert hd(tickets).ticket_id == "JMP-123456"
    end
  end

  describe "update_ticket_slack_channel/2" do
    test "successfully updates Slack channel URL" do
      ticket_id = "page_123"
      channel_id = "C12345"

      {:ok, ticket} = NotionService.update_ticket_slack_channel(ticket_id, channel_id)
      assert ticket.id == "page_123"
      assert ticket.slack_channel == "https://app.slack.com/client/T12345/C12345"
    end
  end

  describe "add_conversation_to_ticket/2" do
    test "adds new conversation URL" do
      ticket_id = "page_123"
      conversation = %{url: "https://app.intercom.com/a/apps/abc123/conversations/456"}

      {:ok, ticket} = NotionService.add_conversation_to_ticket(ticket_id, conversation)
      assert ticket.id == "page_123"
      assert length(ticket.intercom_conversations) == 1

      assert hd(ticket.intercom_conversations) ==
               "https://app.intercom.com/a/apps/abc123/conversations/123"
    end

    test "handles duplicate conversation URLs" do
      ticket_id = "page_123"
      conversation = %{url: "https://app.intercom.com/a/apps/abc123/conversations/123"}

      {:ok, ticket} = NotionService.add_conversation_to_ticket(ticket_id, conversation)
      assert ticket.id == "page_123"
      assert length(ticket.intercom_conversations) == 1

      assert hd(ticket.intercom_conversations) ==
               "https://app.intercom.com/a/apps/abc123/conversations/123"
    end
  end

  describe "create_ticket/1" do
    test "successfully creates a new ticket" do
      ticket_params = %{
        title: "Test Ticket",
        intercom_conversations: ["https://app.intercom.com/a/apps/abc123/conversations/123"],
        slack_channel: nil,
        children: %{
          "current_status" => "Open - New Ticket",
          "main_issue" => "Test Ticket",
          "steps_taken" => "Initial ticket creation",
          "technical_details" => ""
        }
      }

      {:ok, ticket} = NotionService.create_ticket(ticket_params)
      assert ticket.id == "page_123"
      assert ticket.ticket_id == "JMP-123456"
      assert ticket.title == "Test Ticket"
      assert length(ticket.intercom_conversations) == 1
      assert ticket.slack_channel == nil
    end

    test "handles API errors" do
      mock(fn
        %{method: :post, url: "https://api.notion.com/v1/pages"} ->
          json(%{"message" => "Invalid API key"}, status: 401)
      end)

      ticket_params = %{
        title: "Test Ticket",
        intercom_conversations: ["https://app.intercom.com/a/apps/abc123/conversations/123"],
        slack_channel: nil,
        children: %{
          "current_status" => "Open - New Ticket",
          "main_issue" => "Test Ticket",
          "steps_taken" => "Initial ticket creation",
          "technical_details" => ""
        }
      }

      assert {:error, "Invalid Notion API key"} = NotionService.create_ticket(ticket_params)
    end
  end
end
