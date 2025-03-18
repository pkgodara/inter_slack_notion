# InterSlackNotion

A powerful integration between Intercom, Slack, and Notion that streamlines customer support workflow by automatically creating and managing support tickets.

## Features

- Create Notion tickets directly from Intercom conversations
- Automatic ticket deduplication using AI
- Automatic Slack channel creation and user synchronization
- Smart ticket title generation
- Automatic conversation summarization
- Status synchronization across all platforms

## Prerequisites

Before you begin, ensure you have:

1. **Intercom Setup**
   - An Intercom workspace
   - Admin access to create custom actions
   - Intercom API access token
   - App ID from your Intercom workspace

2. **Slack Setup**
   - A Slack workspace
   - Admin access to create channels
   - Bot token with necessary permissions:
     - `channels:manage`
     - `chat:write`
     - `users:read`
     - `users:read.email`

3. **Notion Setup**
   - A Notion workspace
   - Admin access to create databases
   - Integration token with write access
   - A database with the following properties:
     - ID (Type: Unique ID, Prefix: "JMP")
     - Title (Type: Title)
     - Intercom Conversations (Type: URL)
     - Slack Channel (Type: URL)
     - Status (Type: Select)

4. **Gemini Setup**
   - An Gemini API key

## Environment Variables

Create a `.env` file in the root directory with the following variables:

```bash
# Intercom
export INTERCOM_ACCESS_TOKEN="your_intercom_access_token"
export INTERCOM_APP_ID="your_intercom_app_id"

# Slack
export SLACK_BOT_TOKEN="your_slack_bot_token"
export SLACK_TEAM_ID="your_slack_team_id"

# Notion
export NOTION_API_KEY="your_notion_api_key"
export NOTION_DATABASE_ID="your_notion_database_id"

# Gemini
export GEMINI_API_KEY="your_gemini_api_key"
```

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/inter_slack_notion.git
   cd inter_slack_notion
   ```

2. Load environment variables:
   ```bash
   source .env
   ```

3. Install dependencies:
   ```bash
   mix setup
   ```

4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

The server will be available at [`localhost:4000`](http://localhost:4000).

## Intercom Setup

1. Go to your Intercom workspace settings
2. Navigate to Custom Actions
3. Create a new Custom Action:
   - Name: "Create Notion Ticket"
   - Target URL: `http://your-server/api/intercom/create-ticket`
   - Method: POST
   - Authentication: Add your chosen authentication header

## Usage

1. In Intercom, open any conversation
2. Click the three-dot menu
3. Select "Create Notion Ticket"
4. The system will:
   - Check for existing similar tickets
   - Create a new ticket or update an existing one
   - Create/update Slack channels
   - Sync participants across platforms

## Development

- Run tests: `mix test`
- Run linter: `mix credo`
- Generate docs: `mix docs`

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Deployment to Fly.io

### Prerequisites

1. Install the Fly CLI:
   ```bash
   # On macOS
   brew install flyctl
   # On Linux
   curl -L https://fly.io/install.sh | sh
   ```

2. Login to Fly:
   ```bash
   flyctl auth login
   ```

### Deployment Steps

1. Clone and prepare the repository:
   ```bash
   git clone https://github.com/yourusername/inter_slack_notion.git
   cd inter_slack_notion
   ```

2. Launch the app (this creates the app but doesn't deploy):
   ```bash
   flyctl launch --no-deploy
   ```
   This will:
   - Create a new app on Fly.io
   - Generate a `fly.toml` configuration file
   - Set up necessary resources

3. Set up environment variables in Fly:
   ```bash
   flyctl secrets set \
   INTERCOM_ACCESS_TOKEN=$INTERCOM_ACCESS_TOKEN \
   INTERCOM_APP_ID=$INTERCOM_APP_ID \
   SLACK_BOT_TOKEN=$SLACK_BOT_TOKEN \
   SLACK_TEAM_ID=$SLACK_TEAM_ID \
   NOTION_API_KEY=$NOTION_API_KEY \
   NOTION_DATABASE_ID=$NOTION_DATABASE_ID \
   GEMINI_API_KEY=$GEMINI_API_KEY
   ```

4. Deploy the app:
   ```bash
   flyctl deploy --ha=false
   ```

5. Check the deployment status:
   ```bash
   flyctl status
   ```

6. View the app logs:
   ```bash
   flyctl logs
   ```

### Post-Deployment

1. Get your app's URL:
   ```bash
   flyctl apps open
   ```

2. Update your Intercom webhook URL to point to your new deployment:
   - Go to your Intercom workspace settings
   - Navigate to Custom Actions
   - Update the "Create Notion Ticket" action URL to:
     `https://your-app-name.fly.dev/api/intercom/create-ticket`

### Troubleshooting

1. If the app fails to start, check the logs:
   ```bash
   flyctl logs
   ```

2. To check resource usage:
   ```bash
   flyctl status
   ```

3. To restart the app:
   ```bash
   flyctl restart
   ```

4. To check environment variables:
   ```bash
   flyctl secrets list
   ```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
