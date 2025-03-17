defmodule InterSlackNotion.Services.SlackServiceTest do
  use ExUnit.Case, async: true
  alias InterSlackNotion.Services.SlackService
  import Tesla.Mock

  @channel_id "C123"
  @user_id "U1"
  @test_channel_name "test-channel"

  @sample_users [
    %{
      "id" => "U1",
      "name" => "Real User 1",
      "real_name" => "Real User 1",
      "is_bot" => false,
      "deleted" => false,
      "profile" => %{"email" => "user1@example.com"}
    },
    %{
      "id" => "U2",
      "name" => "bot1",
      "real_name" => "Bot User 1",
      "is_bot" => true,
      "deleted" => false,
      "profile" => %{"email" => nil}
    },
    %{
      "id" => "U3",
      "name" => "deleted1",
      "real_name" => "Deleted User 1",
      "is_bot" => false,
      "deleted" => true,
      "profile" => %{"email" => nil}
    }
  ]

  @expected_parsed_users [
    %{
      id: "U1",
      name: "Real User 1",
      email: "user1@example.com",
      is_bot: false,
      deleted: false
    },
    %{
      id: "U2",
      name: "Bot User 1",
      email: nil,
      is_bot: true,
      deleted: false
    },
    %{
      id: "U3",
      name: "Deleted User 1",
      email: nil,
      is_bot: false,
      deleted: true
    }
  ]

  # Helper functions for common mock patterns
  defp mock_success(endpoint, response \\ %{}) do
    mock(fn %{method: _method, url: "https://slack.com/api" <> ^endpoint} = _req ->
      {:ok, %Tesla.Env{status: 200, body: Map.merge(%{"ok" => true}, response)}}
    end)
  end

  defp mock_error(endpoint, error, status \\ 200) do
    mock(fn %{method: _method, url: "https://slack.com/api" <> ^endpoint} = _req ->
      {:ok, %Tesla.Env{status: status, body: %{"ok" => false, "error" => error}}}
    end)
  end

  defp mock_network_error(endpoint) do
    mock(fn %{method: _method, url: "https://slack.com/api" <> ^endpoint} = _req ->
      {:error, :timeout}
    end)
  end

  describe "create_channel/1" do
    test "creates a channel successfully" do
      mock_success("/conversations.create", %{
        "channel" => %{
          "id" => @channel_id,
          "name" => @test_channel_name,
          "is_private" => false
        }
      })

      assert {:ok, %{id: @channel_id, name: @test_channel_name, is_private: false}} =
               SlackService.create_channel(@test_channel_name)
    end

    test "handles error when channel creation fails" do
      mock_error("/conversations.create", "name_taken")

      assert {:error, "Slack API error: name_taken"} =
               SlackService.create_channel(@test_channel_name)
    end

    test "handles network error" do
      mock_network_error("/conversations.create")

      assert {:error, "Request failed: :timeout"} =
               SlackService.create_channel(@test_channel_name)
    end

    test "sanitizes channel name" do
      mock_success("/conversations.create", %{
        "channel" => %{
          "id" => @channel_id,
          "name" => "test-channel",
          "is_private" => false
        }
      })

      assert {:ok, %{name: "test-channel"}} = SlackService.create_channel("Test Channel!")
    end
  end

  describe "set_channel_topic/2" do
    test "sets channel topic successfully" do
      mock_success("/conversations.setTopic")
      assert :ok = SlackService.set_channel_topic(@channel_id, "New topic")
    end

    test "handles error when setting topic fails" do
      mock_error("/conversations.setTopic", "channel_not_found")

      assert {:error, "Slack API error: channel_not_found"} =
               SlackService.set_channel_topic(@channel_id, "New topic")
    end

    test "handles network error" do
      mock_network_error("/conversations.setTopic")

      assert {:error, "Request failed: :timeout"} =
               SlackService.set_channel_topic(@channel_id, "New topic")
    end
  end

  describe "list_users/0" do
    test "lists users successfully" do
      mock_success("/users.list", %{"members" => @sample_users})
      assert {:ok, users} = SlackService.list_users()
      assert users == @expected_parsed_users
    end

    test "handles error when listing users fails" do
      mock_error("/users.list", "invalid_auth")
      assert {:error, "Slack API error: invalid_auth"} = SlackService.list_users()
    end

    test "handles rate limiting" do
      mock(fn %{method: :get, url: "https://slack.com/api/users.list"} ->
        {:ok,
         %Tesla.Env{
           status: 429,
           headers: [{"retry-after", "30"}]
         }}
      end)

      assert {:error, {:rate_limited, 30}} = SlackService.list_users()
    end

    test "handles rate limiting without retry-after header" do
      mock(fn %{method: :get, url: "https://slack.com/api/users.list"} ->
        {:ok, %Tesla.Env{status: 429, headers: []}}
      end)

      assert {:error, {:rate_limited, 60}} = SlackService.list_users()
    end

    test "handles network error" do
      mock_network_error("/users.list")
      assert {:error, "Request failed: :timeout"} = SlackService.list_users()
    end
  end

  describe "invite_to_channel/2" do
    test "invites user to channel successfully" do
      mock_success("/conversations.invite")
      assert :ok = SlackService.invite_to_channel(@channel_id, @user_id)
    end

    test "handles error when inviting user fails" do
      mock_error("/conversations.invite", "channel_not_found")

      assert {:error, "Slack API error: channel_not_found"} =
               SlackService.invite_to_channel(@channel_id, @user_id)
    end

    test "handles network error" do
      mock_network_error("/conversations.invite")

      assert {:error, "Request failed: :timeout"} =
               SlackService.invite_to_channel(@channel_id, @user_id)
    end
  end

  describe "send_message/2" do
    test "sends message successfully" do
      mock_success("/chat.postMessage")
      assert :ok = SlackService.send_message(@channel_id, "Hello, world!")
    end

    test "handles error when sending message fails" do
      mock_error("/chat.postMessage", "channel_not_found")

      assert {:error, "Slack API error: channel_not_found"} =
               SlackService.send_message(@channel_id, "Hello, world!")
    end

    test "handles network error" do
      mock_network_error("/chat.postMessage")

      assert {:error, "Request failed: :timeout"} =
               SlackService.send_message(@channel_id, "Hello, world!")
    end
  end
end
