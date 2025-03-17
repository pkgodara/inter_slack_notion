defmodule InterSlackNotion.DataCase do
  @moduledoc """
  This module defines the setup for tests.
  You may define functions here to be used as helpers in your tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import InterSlackNotion.DataCase
    end
  end

  setup _tags do
    :ok
  end
end
