defmodule InterSlackNotion.Services.NotionService.DatabaseManager do
  @moduledoc """
  Handles Notion database operations.
  """

  use Tesla

  require Logger

  plug Tesla.Middleware.BaseUrl, "https://api.notion.com/v1"
  plug Tesla.Middleware.JSON

  plug Tesla.Middleware.Headers, [
    {"authorization", "Bearer #{Application.get_env(:inter_slack_notion, :notion)[:api_key]}"},
    {"notion-version", "2022-06-28"}
  ]

  @doc """
  Finds the root workspace page or creates one if it doesn't exist.
  """
  def find_workspace_root do
    search_body = %{
      "filter" => %{
        "value" => "page",
        "property" => "object"
      },
      "sort" => %{
        "direction" => "ascending",
        "timestamp" => "last_edited_time"
      }
    }

    case post("/search", search_body) do
      {:ok, %{status: 200, body: %{"results" => [%{"id" => page_id} | _]}}} ->
        {:ok, page_id}

      {:ok, %{status: 200, body: %{"results" => []}}} ->
        create_root_page()

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to search workspace (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to search workspace: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a parent page for a database.
  """
  def create_parent_page(name, parent_id) do
    page_body = %{
      "icon" => %{
        "type" => "emoji",
        "emoji" => "📋"
      },
      "parent" => %{
        "type" => "page_id",
        "page_id" => parent_id
      },
      "properties" => %{
        "title" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => name
            }
          }
        ]
      }
    }

    case post("/pages", page_body) do
      {:ok, %{status: 200, body: page}} ->
        {:ok, page}

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to create parent page (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to create parent page: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a new database.
  """
  def create_database(name, parent_id) do
    database_body = %{
      "parent" => %{
        "type" => "page_id",
        "page_id" => parent_id
      },
      "title" => [
        %{
          "type" => "text",
          "text" => %{
            "content" => name
          }
        }
      ],
      "properties" => %{
        "ID" => %{
          "type" => "title",
          "title" => %{}
        },
        "Title" => %{
          "type" => "rich_text",
          "rich_text" => %{}
        },
        "Intercom Conversations" => %{
          "type" => "url",
          "url" => %{}
        },
        "Slack Channel" => %{
          "type" => "url",
          "url" => %{}
        }
      }
    }

    case post("/databases", database_body) do
      {:ok, %{status: 200, body: database}} ->
        {:ok, database}

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to create database (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to create database: #{inspect(error)}"}
    end
  end

  # Private functions

  defp create_root_page do
    page_body = %{
      "icon" => %{
        "type" => "emoji",
        "emoji" => "🏠"
      },
      "parent" => %{
        "type" => "workspace",
        "workspace" => true
      },
      "properties" => %{
        "title" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => "Support Workspace"
            }
          }
        ]
      }
    }

    case post("/pages", page_body) do
      {:ok, %{status: 200, body: %{"id" => page_id}}} ->
        {:ok, page_id}

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to create root page (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to create root page: #{inspect(error)}"}
    end
  end
end
