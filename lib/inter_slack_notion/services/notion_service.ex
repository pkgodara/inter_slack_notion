defmodule InterSlackNotion.Services.NotionService do
  @moduledoc """
  Service for interacting with the Notion API.
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
  Lists all tickets from the Notion database.
  """
  def list_tickets(status \\ "Open") do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]

    body = %{
      filter: %{
        property: "Status",
        status: %{
          equals: status
        }
      },
      sorts: [
        %{
          timestamp: "created_time",
          direction: "descending"
        }
      ]
    }

    case post("/databases/#{database_id}/query", body) do
      {:ok, %{status: 200, body: %{"results" => results}}} ->
        # IO.inspect(results, label: "list_tickets")
        tickets = Enum.map(results, &parse_ticket/1)
        {:ok, tickets}

      {:ok, %{status: 401}} ->
        {:error, "Invalid Notion API key"}

      {:ok, %{status: 404}} ->
        {:error, "Notion database not found"}

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Notion API error (#{status}): #{message}"}

      {:ok, %{status: status}} ->
        {:error, "Failed to list tickets. Status: #{status}"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to Notion API"}

      {:error, error} ->
        {:error, "Failed to list tickets: #{inspect(error)}"}
    end
  end

  @doc """
  Creates a new ticket in the Notion database.
  """
  def create_ticket(ticket_data) do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]

    ticket_id = generate_random_id()

    properties = %{
      "ID" => %{
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => ticket_id
            }
          }
        ]
      },
      "Title" => %{
        "title" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => ticket_data.title
            }
          }
        ]
      },
      "Intercom Conversations" => %{
        "type" => "rich_text",
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => Enum.join(ticket_data.intercom_conversations || [], ", "),
              "link" => %{"url" => List.first(ticket_data.intercom_conversations || [])}
            }
          }
        ]
      },
      "Slack Channel" => %{
        "url" => ticket_data.slack_channel
      }
    }

    # Create the page with both properties and children
    body = %{
      "parent" => %{
        "database_id" => database_id
      },
      "icon" => %{
        "type" => "emoji",
        "emoji" => "🎫"
      },
      "properties" => properties,
      "children" => [
        %{
          "object" => "block",
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Current Status"}}]
          }
        },
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{
                  "content" => ticket_data.children["current_status"] || "Open - New Ticket"
                }
              }
            ]
          }
        },
        %{
          "object" => "block",
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Main Issue"}}]
          }
        },
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{
                  "content" => ticket_data.children["main_issue"] || ticket_data.title
                }
              }
            ]
          }
        },
        %{
          "object" => "block",
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Steps Taken"}}]
          }
        },
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{
                  "content" => ticket_data.children["steps_taken"] || "Initial ticket creation"
                }
              }
            ]
          }
        },
        %{
          "object" => "block",
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"type" => "text", "text" => %{"content" => "Technical Details"}}]
          }
        },
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{
                  "content" => ticket_data.children["technical_details"] || ""
                }
              }
            ]
          }
        }
      ]
    }

    case post("/pages", body) do
      {:ok, %{status: 200, body: page}} ->
        {:ok, parse_ticket(page)}

      {:ok, resp} ->
        {:error, "Failed to create ticket. Response: #{inspect(resp)}"}

      {:error, %Tesla.Error{reason: :econnrefused}} ->
        {:error, "Could not connect to Notion API"}

      {:error, error} ->
        {:error, "Failed to create ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Gets a specific ticket by its ID. Can be either a Notion page UUID or a JMP-NNNN format ticket ID.
  """
  def get_ticket(id) do
    # First try to get by page UUID directly
    case get("/pages/#{id}") do
      {:ok, %{status: 200, body: page}} ->
        {:ok, parse_ticket(page)}

      {:ok, %{status: 400}} when is_binary(id) ->
        # Check if it's a JMP ID
        if String.starts_with?(id, "JMP-") do
          # If it's a JMP ID and direct lookup failed, search for it
          case find_page_id_by_ticket_id(id) do
            {:ok, page_id} -> get_ticket(page_id)
            error -> error
          end
        else
          {:error, "Invalid ticket ID format"}
        end

      {:error, error} ->
        {:error, "Failed to get ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Finds the Notion page UUID for a given ticket ID (JMP-NNNN format).
  """
  def find_page_id_by_ticket_id(ticket_id) when is_binary(ticket_id) do
    database_id = Application.get_env(:inter_slack_notion, :notion)[:database_id]

    body = %{
      filter: %{
        property: "ID",
        rich_text: %{
          equals: ticket_id
        }
      }
    }

    case post("/databases/#{database_id}/query", body) do
      {:ok, %{status: 200, body: %{"results" => [page | _]}}} ->
        {:ok, page["id"]}

      {:ok, %{status: 200, body: %{"results" => []}}} ->
        {:error, "Ticket not found: #{ticket_id}"}

      {:error, error} ->
        {:error, "Failed to find ticket: #{inspect(error)}"}
    end
  end

  @doc """
  Updates a ticket's Slack channel URL.
  """
  def update_ticket_slack_channel(ticket_id, slack_channel_id) do
    Logger.info("Updating ticket #{ticket_id} with Slack channel ID: #{slack_channel_id}")

    case Application.get_env(:inter_slack_notion, :slack_team_id) do
      nil ->
        Logger.error("SLACK_TEAM_ID environment variable is not set")
        {:error, "SLACK_TEAM_ID environment variable is not set"}

      team_id ->
        # Format according to memory: https://app.slack.com/client/{SLACK_TEAM_ID}/{CHANNEL_ID}
        url = "https://app.slack.com/client/#{team_id}/#{slack_channel_id}"
        Logger.info("Setting Slack channel URL to: #{url}")

        # Verify URL format
        case URI.parse(url) do
          %URI{scheme: "https", host: "app.slack.com", path: "/client/" <> rest} ->
            case String.split(rest, "/") do
              [^team_id, ^slack_channel_id] ->
                Logger.info(
                  "URL format verified: team_id=#{team_id}, channel_id=#{slack_channel_id}"
                )

                properties = %{
                  "Slack Channel" => %{
                    "url" => url
                  }
                }

                case update_ticket(ticket_id, properties) do
                  {:ok, updated_ticket} ->
                    if updated_ticket.slack_channel == url do
                      Logger.info("Successfully updated ticket with Slack URL: #{url}")
                      {:ok, updated_ticket}
                    else
                      Logger.error(
                        "Failed to update Slack URL. Expected: #{url}, Got: #{updated_ticket.slack_channel}"
                      )

                      {:error, "Failed to update Slack channel URL in Notion"}
                    end

                  {:error, error} ->
                    Logger.error("Failed to update ticket with Slack URL: #{inspect(error)}")
                    {:error, error}
                end

              _ ->
                Logger.error("Invalid Slack URL format: #{url}")
                {:error, "Invalid Slack URL format"}
            end

          _ ->
            Logger.error("Invalid Slack URL format: #{url}")
            {:error, "Invalid Slack URL format"}
        end
    end
  end

  @doc """
  Adds a conversation URL to the ticket's Intercom Conversations list.
  The Intercom Conversations field in Notion is a URL property that stores multiple URLs as a comma-separated string.
  """
  def add_conversation_to_ticket(id, conversation) do
    # First get the ticket, which will handle JMP-NNNN -> UUID conversion if needed
    with {:ok, ticket} <- get_ticket(id),
         conversation_url when not is_nil(conversation_url) <- conversation.url do
      # Get current URLs as a list, handling all possible cases
      current_urls =
        case ticket.intercom_conversations do
          nil -> []
          url when is_binary(url) -> [String.trim(url)]
          urls when is_list(urls) -> Enum.map(urls, &String.trim/1)
          _ -> []
        end

      # Add new URL if it doesn't exist yet
      updated_urls =
        if conversation_url in current_urls do
          current_urls
        else
          # Append new URL to preserve chronological order
          current_urls ++ [conversation_url]
        end

      # Update the Notion properties with the URLs
      properties = %{
        "Intercom Conversations" => %{
          "type" => "rich_text",
          "rich_text" => [
            %{
              "type" => "text",
              "text" => %{
                "content" => Enum.join(updated_urls, ", "),
                "link" => %{"url" => List.first(updated_urls)}
              }
            }
          ]
        }
      }

      # Update the ticket properties
      with {:ok, updated_ticket} <- update_ticket(ticket.id, properties) do
        {:ok, updated_ticket}
      end
    else
      nil -> {:error, "Invalid conversation URL"}
      error -> error
    end
  end

  defp update_ticket(page_id, properties) do
    Logger.info("Updating Notion page #{page_id} with properties: #{inspect(properties)}")

    case patch("/pages/#{page_id}", %{"properties" => properties}) do
      {:ok, %{status: 200, body: page}} ->
        updated_ticket = parse_ticket(page)
        Logger.info("Successfully updated ticket properties: #{inspect(updated_ticket)}")
        {:ok, updated_ticket}

      {:ok, %{status: status, body: %{"object" => "error", "message" => message}}} ->
        Logger.error("Failed to update ticket (#{status}): #{message}")
        {:error, "Failed to update ticket: #{message}"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to update ticket (#{status}): #{inspect(body)}")
        {:error, "Failed to update ticket: Status #{status}, #{inspect(body)}"}

      {:error, %Tesla.Error{reason: reason}} when reason in [:timeout, :econnrefused] ->
        Logger.error("Connection error updating ticket: #{reason}")
        {:error, "Connection error: #{reason}"}

      {:error, error} ->
        Logger.error("Failed to update ticket: #{inspect(error)}")
        {:error, "Failed to update ticket: #{inspect(error)}"}
    end
  end

  defp parse_ticket(page) do
    properties = page["properties"]

    %{
      id: page["id"],
      title: get_title(properties["Title"]),
      ticket_id: get_unique_id(properties["ID"]),
      status: get_select(properties["Status"]),
      intercom_conversations: get_url(properties["Intercom Conversations"]),
      slack_channel: get_url(properties["Slack Channel"]),
      url: page["url"],
      children: get_rich_text(properties["children"])
    }
  end

  defp get_title(nil), do: nil

  defp get_title(property) do
    case property["title"] do
      [%{"text" => %{"content" => content}} | _] -> content
      _ -> nil
    end
  end

  defp get_unique_id(nil), do: nil

  defp get_unique_id(property) do
    case property["rich_text"] do
      [%{"text" => %{"content" => content}} | _] -> content
      _ -> nil
    end
  end

  defp get_select(nil), do: nil
  defp get_select(property), do: property["select"]["name"]

  defp get_url(nil), do: nil

  defp get_url(property) do
    case property do
      %{"type" => "rich_text", "rich_text" => [%{"text" => %{"content" => content}} | _]}
      when not is_nil(content) ->
        Logger.info("Found rich_text URLs: #{content}")

        content
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> case do
          [] -> nil
          [single_url] -> single_url
          urls -> urls
        end

      %{"type" => "url", "url" => url} when not is_nil(url) ->
        Logger.info("Found URL property: #{url}")
        String.trim(url)

      %{"url" => url} when not is_nil(url) ->
        Logger.info("Found legacy URL property: #{url}")
        String.trim(url)

      _ ->
        Logger.warning("Invalid URL property format: #{inspect(property)}")
        nil
    end
  end

  defp get_rich_text(nil), do: nil

  defp get_rich_text(property) do
    case property["rich_text"] do
      [%{"text" => %{"content" => content}} | _] -> content
      _ -> nil
    end
  end

  defp generate_random_id do
    random_num = :rand.uniform(999_999)
    "JMP-#{String.pad_leading(Integer.to_string(random_num), 6, "0")}"
  end

  @doc """
  Creates a new Notion database with a parent page.
  Returns {:ok, database_id} on success or {:error, reason} on failure.
  """
  def create_database(name) do
    # First find or create parent page in workspace
    with {:ok, parent_id} <- find_workspace_root(),
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
         },
         {:ok, %{status: 200, body: page}} <- post("/pages", page_body),
         parent_id <- page["id"] do
      # Then create the database as a child of the page
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
          {:ok, database["id"]}

        {:ok, %{status: status, body: %{"message" => message}}} ->
          {:error, "Failed to create database (#{status}): #{message}"}

        {:error, error} ->
          {:error, "Failed to create database: #{inspect(error)}"}
      end
    else
      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to create parent page (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to create parent page: #{inspect(error)}"}
    end
  end

  # Finds the root workspace page or creates one if it doesn't exist.
  # Returns {:ok, page_id} on success or {:error, reason} on failure.
  defp find_workspace_root do
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
        # No pages found, create a new root page
        create_root_page()

      {:ok, %{status: status, body: %{"message" => message}}} ->
        {:error, "Failed to search workspace (#{status}): #{message}"}

      {:error, error} ->
        {:error, "Failed to search workspace: #{inspect(error)}"}
    end
  end

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
