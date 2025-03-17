defmodule InterSlackNotion.Services.IntercomServiceTest do
  use ExUnit.Case, async: true
  alias InterSlackNotion.Services.IntercomService
  import Tesla.Mock

  @sample_conversation_id "123"
  @sample_admin_id "456"

  setup do
    Application.put_env(:inter_slack_notion, :intercom_access_token, "test-token")

    mock(fn
      %{method: :get, url: "https://api.intercom.io/me"} ->
        {:ok, %Tesla.Env{status: 200, body: %{"id" => @sample_admin_id}}}

      %{method: :get, url: "https://api.intercom.io/conversations/" <> @sample_conversation_id} ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "id" => @sample_conversation_id,
             "created_at" => 1_616_733_600,
             "updated_at" => 1_616_733_700,
             "source" => %{
               "subject" => "Test Subject",
               "author" => %{
                 "name" => "Test User",
                 "email" => "test@example.com"
               }
             },
             "conversation_parts" => %{
               "conversation_parts" => [
                 %{
                   "body" => "Test message",
                   "author" => %{
                     "name" => "Test User",
                     "email" => "test@example.com"
                   },
                   "created_at" => 1_616_733_600
                 }
               ]
             }
           }
         }}

      %{
        method: :post,
        url: "https://api.intercom.io/conversations/" <> @sample_conversation_id <> "/reply"
      } ->
        {:ok, %Tesla.Env{status: 200, body: %{"id" => "reply_123"}}}
    end)

    :ok
  end

  describe "get_conversation/1" do
    test "returns conversation data when successful" do
      conversation_data = %{
        "id" => "123",
        "source" => %{"subject" => "Test Conversation"},
        "conversation_parts" => %{
          "conversation_parts" => [
            %{
              "body" => "Hello",
              "author" => %{"name" => "John Doe", "email" => "john@example.com"},
              "created_at" => 1_234_567_890,
              "part_type" => "comment"
            }
          ]
        },
        "created_at" => 1_234_567_890,
        "updated_at" => 1_234_567_890
      }

      mock(fn
        %{method: :get, url: "https://api.intercom.io/conversations/123"} ->
          %Tesla.Env{status: 200, body: conversation_data}
      end)

      assert {:ok, conversation} = IntercomService.get_conversation("123")
      assert conversation.id == "123"
      assert conversation.title == "Test Conversation"
      assert length(conversation.messages) == 1
      assert hd(conversation.messages).body == "Hello"
      assert conversation.created_at == 1_234_567_890
      assert conversation.updated_at == 1_234_567_890
    end

    test "returns error when conversation not found" do
      mock(fn
        %{method: :get, url: "https://api.intercom.io/conversations/123"} ->
          %Tesla.Env{status: 404, body: %{"message" => "Conversation not found"}}
      end)

      assert {:error, "Conversation not found"} = IntercomService.get_conversation("123")
    end

    test "returns error when access token is invalid" do
      mock(fn
        %{method: :get, url: "https://api.intercom.io/conversations/123"} ->
          %Tesla.Env{status: 401, body: %{"message" => "Invalid access token"}}
      end)

      assert {:error, "Invalid Intercom access token"} = IntercomService.get_conversation("123")
    end
  end

  describe "send_message/2" do
    test "sends message successfully" do
      mock(fn
        %{method: :get, url: "https://api.intercom.io/me"} ->
          %Tesla.Env{status: 200, body: %{"id" => "admin123"}}

        %{method: :post, url: "https://api.intercom.io/conversations/123/reply"} ->
          %Tesla.Env{status: 200, body: %{"id" => "reply123"}}
      end)

      assert {:ok, "reply123"} = IntercomService.send_message("123", "Hello")
    end

    test "returns error when message fails" do
      mock(fn
        %{method: :get, url: "https://api.intercom.io/me"} ->
          %Tesla.Env{status: 200, body: %{"id" => "admin123"}}

        %{method: :post, url: "https://api.intercom.io/conversations/123/reply"} ->
          %Tesla.Env{status: 400, body: %{"message" => "Invalid message"}}
      end)

      assert {:error, "Invalid message"} = IntercomService.send_message("123", "Hello")
    end
  end

  describe "parse_conversation/1" do
    test "parses valid conversation data" do
      conversation_data = %{
        "id" => "123",
        "source" => %{"subject" => "Test Conversation"},
        "conversation_parts" => %{
          "conversation_parts" => [
            %{
              "body" => "Hello",
              "author" => %{"name" => "John Doe", "email" => "john@example.com"},
              "created_at" => 1_234_567_890,
              "part_type" => "comment"
            }
          ]
        },
        "created_at" => 1_234_567_890,
        "updated_at" => 1_234_567_890
      }

      assert {:ok, conversation} = IntercomService.parse_conversation(conversation_data)
      assert conversation.id == "123"
      assert conversation.title == "Test Conversation"
      assert length(conversation.messages) == 1
      assert hd(conversation.messages).body == "Hello"
      assert conversation.created_at == 1_234_567_890
      assert conversation.updated_at == 1_234_567_890
    end

    test "returns error for invalid conversation data" do
      conversation_data = %{
        "id" => "123",
        "source" => %{"subject" => nil},
        "conversation_parts" => %{
          "conversation_parts" => []
        },
        "created_at" => 1_234_567_890,
        "updated_at" => 1_234_567_890
      }

      assert {:error, "Invalid conversation data"} =
               IntercomService.parse_conversation(conversation_data)
    end
  end
end
