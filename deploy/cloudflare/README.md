# Cloudflare Pilot Deployment

This folder contains the Cloudflare Worker and Container scaffold for a beta
Agent Awesome Slack pilot.

The deployment runs one Cloudflare Container behind a Worker. Inside the
container, `agent-gateway` listens on port `8070` and supervises the local
harness on `8080` plus memory MCP on `8090`. Slack uses the HTTP Events API at
`/slack/events`; Socket Mode remains for local testing only. The Worker rejects
all public requests except unauthenticated `GET` or `HEAD /healthz`, bearer
authenticated gateway control-plane requests, and Slack-signed
`POST /slack/events` requests.

Memory context is restored from and saved to the `agent-awesome-beta-context` R2
bucket through a private Worker endpoint. The endpoint requires
`AGENTAWESOME_PERSISTENCE_TOKEN` and is only intended for the colocated
container.

## Files

- `../../Dockerfile.cloudflare` builds the Go gateway, harness, and memory
  binaries into one Linux container.
- `scripts/entrypoint.sh` starts the gateway with harness and memory auto-start
  flags.
- `config/*.yaml` contains the pilot model, agent, and tool configuration used
  inside the container.
- `worker/src/index.ts` defines the Cloudflare Container class and request
  routing.
- `worker/wrangler.jsonc` declares the Container, Durable Object binding,
  observability, non-secret vars, and required secrets.

## Deploy

Use Node.js `22` or newer for Wrangler.

Run these commands from `deploy/cloudflare/worker`:

```sh
npm install --cache ../../../build/npm-cache
npm test
npx wrangler r2 bucket create agent-awesome-beta-context
npx wrangler secret put AGENTAWESOME_GATEWAY_TOKEN
npx wrangler secret put AGENTAWESOME_PERSISTENCE_TOKEN
npx wrangler secret put SLACK_SIGNING_SECRET
npx wrangler secret put SLACK_BOT_TOKEN
npx wrangler secret put OPENAI_API_KEY
npx wrangler deploy
```

The R2 bucket command requires a Cloudflare API token or OAuth session with
`Workers R2 Storage Write`. If Wrangler asks for `CLOUDFLARE_API_TOKEN`, create a
temporary token with that permission, export it for the command, then unset it.

After the first deployment, wait for the container application to finish
provisioning, then set the Slack app Event Request URL to:

```text
https://agent-awesome.com/slack/events
```

Use the same Slack bot token and signing secret you tested locally. Do not set
`SLACK_APP_TOKEN` for this deployment unless you deliberately switch the cloud
config back to Socket Mode.

The public `workers.dev` URL is disabled. `agent-awesome.com/*` is the configured
Cloudflare Worker route for the existing domain. The Worker forwards Slack-signed
Events API requests and bearer-authenticated gateway control-plane requests.

## Desktop UI Check

Run the release binary with the hosted gateway and cloud profile:

```sh
export AGENT_GATEWAY_BASE_URL=https://agent-awesome.com/api
export AGENTAWESOME_GATEWAY_TOKEN="<gateway-token>"
export AGENTAWESOME_RUNTIME_PROFILE="<release-root>/ui/runtime_profiles/cloudflare_context.json"
export AUTO_START_LOCAL_SERVICES=false
./agentawesome_ui
```

The desktop UI should use the same gateway as Slack for chat, memory, and task
traffic.

## Security Notes

Set `AGENTAWESOME_GATEWAY_TOKEN` before deployment. Slack requests are verified
with Slack signatures by the gateway, while `/api/*`, `/mcp`, and gateway status
routes use the bearer token. The public `/healthz` route only returns the
gateway liveness response.

Keep `SLACK_ALLOWED_TEAM_ID`, `SLACK_ALLOWED_USER_ID`, and
`SLACK_ALLOWED_CHANNEL_ID` populated in `worker/wrangler.jsonc` before any Slack
beta deployment. The gateway refuses to start Slack ingress without all three
allow-list ids.

## Persistence Note

The bundled memory database lives under `/app/data` inside the container. This
is enough for an HTTP pilot while the container stays alive, but Cloudflare
Container disk is ephemeral after the instance sleeps. The checked-in Worker
config points at a beta sandbox R2 bucket; use provisioner-generated per-agent
buckets for tester deployments and keep personal memory buckets out of the beta
path.
