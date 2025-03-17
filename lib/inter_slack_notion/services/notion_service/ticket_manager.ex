defmodule InterSlackNotion.Services.NotionService.TicketManager do
  @moduledoc """
  Handles ticket-specific operations.
  """

  @doc """
  Generates a random ticket ID in the format JMP-NNNNNN.
  """
  def generate_random_id do
    random_num = :rand.uniform(999_999)
    "JMP-#{String.pad_leading(Integer.to_string(random_num), 6, "0")}"
  end
end
