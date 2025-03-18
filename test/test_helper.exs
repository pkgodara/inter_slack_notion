ExUnit.start()

# Set up Mox
Application.ensure_all_started(:mox)

# Set up Tesla mock adapter for HTTP requests
Application.put_env(:tesla, :adapter, Tesla.Mock)

# Configure Mox to allow async testing
Mox.defmock(InterSlackNotion.Services.NotionServiceMock,
  for: InterSlackNotion.Behaviours.NotionService
)

Mox.defmock(InterSlackNotion.Services.GeminiServiceMock,
  for: InterSlackNotion.Behaviours.LLMService
)

Mox.defmock(InterSlackNotion.Integrations.TicketManagerMock,
  for: InterSlackNotion.Behaviours.TicketManager
)
