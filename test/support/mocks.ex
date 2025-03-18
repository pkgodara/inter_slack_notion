defmodule InterSlackNotion.Test.Mocks do
  # Define mocks for our services
  Mox.defmock(InterSlackNotion.Services.NotionServiceMock,
    for: InterSlackNotion.Behaviours.NotionService
  )

  Mox.defmock(InterSlackNotion.Services.GeminiServiceMock,
    for: InterSlackNotion.Behaviours.LLMService
  )

  Mox.defmock(InterSlackNotion.Integrations.TicketManagerMock,
    for: InterSlackNotion.Behaviours.TicketManager
  )
end
