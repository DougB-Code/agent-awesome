# Slack Workspace Migration Runbook

This runbook moves the Cloudflare-hosted Agent Awesome gateway to a new private
Slack workspace. It rotates only Slack-specific secrets and workspace allow-list
values; model, gateway, and persistence secrets remain unchanged.

## Current Cloudflare Shape

The deployed gateway receives Slack Events API traffic at:

```text
https://agent-awesome.com/slack/events
```

The Worker blocks all other public requests and only forwards Slack-signed
`POST /slack/events` requests to the container. The gateway then verifies the
same Slack signature again before dispatching to the agent.

## Slack App Setup

1. In the new Slack workspace, create or import the app from
   `gateway/slack-manifest.json`.
2. In Slack app **Event Subscriptions**, set the Request URL to:

   ```text
   https://agent-awesome.com/slack/events
   ```

3. For the Cloudflare deployment, keep Socket Mode disabled. The local test
   workflow can still use Socket Mode, but Cloudflare uses HTTP Events.
4. Install the app to the new workspace.
5. Copy these values from the Slack app dashboard:
   - **Basic Information > App Credentials > Signing Secret**
   - **OAuth & Permissions > Bot User OAuth Token**
   - Optional: workspace team ID, your Slack user ID, and the target channel ID
     if you want allow-listing.

Do not paste Slack secrets into chat, docs, or shell history.

## Rotate Cloudflare Secrets

Run these commands from the Worker deployment folder:

```sh
cd /home/doug/dev/agentawesome/agent/deploy/cloudflare/worker
```

Upload the new Slack signing secret:

```sh
npx wrangler secret put SLACK_SIGNING_SECRET
```

Upload the new Slack bot token:

```sh
npx wrangler secret put SLACK_BOT_TOKEN
```

Keep these existing secrets unless you intentionally rotate them:

```text
AGENTAWESOME_GATEWAY_TOKEN
AGENTAWESOME_PERSISTENCE_TOKEN
OPENAI_API_KEY
```

## Update Optional Allow-Lists

The Cloudflare Worker config supports these non-secret Slack allow-list values:

```json
"SLACK_ALLOWED_TEAM_ID": "",
"SLACK_ALLOWED_USER_ID": "",
"SLACK_ALLOWED_CHANNEL_ID": ""
```

For a private single-user pilot, set at least `SLACK_ALLOWED_TEAM_ID` and
`SLACK_ALLOWED_USER_ID` in `deploy/cloudflare/worker/wrangler.jsonc`.

Leave `SLACK_ALLOWED_CHANNEL_ID` empty if you want to chat with the agent from
any direct message or allowed app surface in the new workspace.

## Redeploy

Validate locally:

```sh
npm run check
npx wrangler deploy --dry-run
```

Deploy:

```sh
npx wrangler deploy
```

The deploy should show the `agent-awesome.com/*` route and the R2 bucket binding:

```text
agent-awesome.com/* (zone name: agent-awesome.com)
env.CONTEXT_SNAPSHOTS (agent-awesome-context) R2 Bucket
```

## Verify In Slack

1. In Slack app **Event Subscriptions**, confirm the Request URL is verified.
2. Open the app's Messages tab or direct message the bot in the new workspace.
3. Send a short test message.
4. Confirm the agent replies in a Slack thread.

If Slack URL verification fails, check:

- `SLACK_SIGNING_SECRET` was uploaded from the new Slack app.
- The Event Request URL is exactly `https://agent-awesome.com/slack/events`.
- The Worker is deployed after the secret rotation.
- Socket Mode is disabled for the Cloudflare app path.

If messages are accepted but ignored, check:

- `SLACK_ALLOWED_TEAM_ID` matches the new workspace team ID.
- `SLACK_ALLOWED_USER_ID` matches your new workspace user ID.
- `SLACK_ALLOWED_CHANNEL_ID` is empty or matches the channel where you tested.

## Operational Notes

The old workspace's bot token stops mattering as soon as `SLACK_BOT_TOKEN` is
rotated. Events from the old workspace will also fail if the signing secret was
changed and that workspace still points at `agent-awesome.com/slack/events`.

Context persistence is independent of Slack workspace migration. The Cloudflare
container continues to restore and save context snapshots through the
`agent-awesome-context` R2 bucket.
