defmodule InterSlackNotion.Services.NotionService.PropertyParser do
  @moduledoc """
  Handles parsing and creating Notion properties.
  """

  require Logger

  @doc """
  Parses a Notion page into a ticket struct.
  """
  def parse_ticket(page) do
    properties = page["properties"]

    %{
      id: page["id"],
      title: get_title(properties["Title"]),
      ticket_id: get_unique_id(properties["ID"]),
      status: get_select(properties["Status"]),
      intercom_conversations: get_url(properties["Intercom Conversations"], :list),
      slack_channel: get_url(properties["Slack Channel"], :single),
      url: page["url"],
      children: get_rich_text(properties["children"])
    }
  end

  @doc """
  Creates a rich text property.
  """
  def create_rich_text_property(content) do
    %{
      "rich_text" => [
        %{
          "type" => "text",
          "text" => %{
            "content" => content
          }
        }
      ]
    }
  end

  @doc """
  Creates a title property.
  """
  def create_title_property(content) do
    %{
      "title" => [
        %{
          "type" => "text",
          "text" => %{
            "content" => content
          }
        }
      ]
    }
  end

  @doc """
  Creates a URL property.
  """
  def create_url_property(url) do
    %{
      "type" => "url",
      "url" => url
    }
  end

  @doc """
  Creates a conversations property with multiple URLs.
  """
  def create_conversations_property(urls) do
    %{
      "rich_text" => [
        %{
          "type" => "text",
          "text" => %{
            "content" => Enum.join(urls || [], ", ")
          }
        }
      ]
    }
  end

  # Private functions

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
  defp get_select(%{"status" => %{"name" => name}}), do: name
  defp get_select(%{"select" => %{"name" => name}}), do: name
  defp get_select(_), do: nil

  defp get_url(nil, _), do: nil

  defp get_url(property, return_type) do
    urls =
      case property do
        %{"url" => url} when not is_nil(url) ->
          Logger.info("Found URL property: #{url}")
          [String.trim(url)]

        %{"rich_text" => [%{"text" => %{"content" => content}} | _]} ->
          Logger.info("Found rich_text URLs: #{content}")

          content
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        _ ->
          Logger.warning("Invalid URL property format: #{inspect(property)}")
          []
      end

    case {return_type, urls} do
      {:single, [url | _]} -> url
      {:single, _} -> nil
      {:list, []} -> nil
      {:list, urls} -> urls
    end
  end

  defp get_rich_text(nil), do: nil

  defp get_rich_text(property) do
    case property["rich_text"] do
      [%{"text" => %{"content" => content}} | _] -> content
      _ -> nil
    end
  end
end
