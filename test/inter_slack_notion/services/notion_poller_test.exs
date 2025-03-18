defmodule InterSlackNotion.Services.NotionPollerTest do
  use ExUnit.Case, async: false
  import Tesla.Mock
  alias InterSlackNotion.Services.NotionPoller

  @test_api_key "test_api_key"
  @test_database_id "test_database_id"

  setup do
    Application.put_env(:inter_slack_notion, :notion, %{
      api_key: @test_api_key,
      database_id: @test_database_id,
      poll_interval_ms: 1000
    })

    Tesla.Mock.mock_global(fn
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
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer and initializes state" do
      {:ok, pid} = NotionPoller.start_link([])
      # Give the GenServer time to initialize
      Process.sleep(100)
      assert Process.alive?(pid)

      # Verify the state was initialized with the mocked ticket
      state = :sys.get_state(pid)
      assert Map.has_key?(state, :resolved_tickets)
      assert MapSet.member?(state.resolved_tickets, "page_123")
    end
  end

  describe "handle_info/2" do
    test "polls for new tickets" do
      {:ok, pid} = NotionPoller.start_link([])
      # Give the GenServer time to initialize
      Process.sleep(100)

      # Get the initial state
      initial_state = :sys.get_state(pid)

      # Send a poll message
      send(pid, :poll)
      # Give time for the poll to complete
      Process.sleep(100)

      # Get the new state
      new_state = :sys.get_state(pid)

      # The states should be the same since we're using the same mock
      assert new_state == initial_state
      assert MapSet.member?(new_state.resolved_tickets, "page_123")
    end
  end
end
