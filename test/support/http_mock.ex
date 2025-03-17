defmodule InterSlackNotion.Test.HTTPMock do
  @moduledoc """
  Mock HTTP responses for testing external API calls.
  """

  def mock_success(status \\ 200, body) do
    {:ok, %Tesla.Env{status: status, body: body}}
  end

  def mock_error(status, body \\ %{"error" => "Some error"}) do
    {:ok, %Tesla.Env{status: status, body: body}}
  end

  def mock_network_error(reason \\ :econnrefused) do
    {:error, %Tesla.Error{reason: reason}}
  end
end
