defmodule InterSlackNotion.Services.NotionService.PageManager do
  @moduledoc """
  Handles Notion page operations and content.
  """

  @doc """
  Creates the children blocks for a ticket page.
  """
  def create_ticket_children(ticket_data) do
    [
      create_heading_block("Current Status"),
      create_paragraph_block(ticket_data.children["current_status"] || "Open - New Ticket"),
      create_heading_block("Main Issue"),
      create_paragraph_block(ticket_data.children["main_issue"] || ticket_data.title),
      create_heading_block("Steps Taken"),
      create_paragraph_block(ticket_data.children["steps_taken"] || "Initial ticket creation"),
      create_heading_block("Technical Details"),
      create_paragraph_block(ticket_data.children["technical_details"] || "")
    ]
  end

  # Private functions

  defp create_heading_block(content) do
    %{
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => %{
        "rich_text" => [%{"type" => "text", "text" => %{"content" => content}}]
      }
    }
  end

  defp create_paragraph_block(content) do
    %{
      "object" => "block",
      "type" => "paragraph",
      "paragraph" => %{
        "rich_text" => [
          %{
            "type" => "text",
            "text" => %{
              "content" => content
            }
          }
        ]
      }
    }
  end
end
