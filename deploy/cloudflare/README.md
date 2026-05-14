# Cloudflare Pilot Deployment

This folder contains the Cloudflare Worker and Container scaffold for a beta
Agent Awesome Slack pilot.

The deployment runs one Cloudflare Container behind a Worker. Inside the
container, `agent-gateway` listens on port `8070`, routes profile-scoped
requests to separate harness processes, and supervises separate memory MCP
services for the configured domains. The checked-in beta config starts Doug on
ports `8080`/`8081` with memory on `8090`, and Family on ports `8082`/`8083`
with memory on `8091`. Slack uses the HTTP Events API at
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
- `scripts/entrypoint.sh` starts the profile-specific harness processes and the
  gateway-supervised memory services.
- `config/*.yaml` contains the pilot model, agent, and tool configuration used
  inside the container.
- `worker/src/index.ts` defines the Cloudflare Container class and request
  routing.
- `worker/wrangler.jsonc` declares the Container, Durable Object binding,
  observability, non-secret vars, and required secrets.

The checked-in cloud model config defaults to OpenAI `gpt-5.4-mini`. If you
switch the beta container model, set `AGENTAWESOME_MODEL_ID` in
`worker/wrangler.jsonc` and confirm that the deployed `OPENAI_API_KEY` has
access to that model before deploying. The container renders
`/app/runtime/model.yaml` from these Worker vars on startup and logs the actual
provider/model pair.

For isolated release tests, set `AGENTAWESOME_OPENAI_CHAT_COMPLETIONS_URL` to an
OpenAI-compatible mock endpoint. Production deployments should leave it unset so
the container uses `https://api.openai.com/v1/chat/completions`.

## Deploy

Use Node.js `22` or newer for Wrangler.

## Local Container Check

Build and run the Cloudflare container locally before deploying:

```sh
docker build --file Dockerfile.cloudflare --tag agent-awesome-cloudflare:debug .
docker run --rm -d \
  --name agent-awesome-cloudflare-debug \
  -p 8070:8070 \
  -e AGENTAWESOME_GATEWAY_TOKEN=test \
  -e AGENTAWESOME_PERSISTENCE_TOKEN=test \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-test}" \
  -e SLACK_ENABLED=false \
  agent-awesome-cloudflare:debug
curl -fsS http://127.0.0.1:8070/healthz
curl -fsS \
  -H "Authorization: Bearer test" \
  http://127.0.0.1:8070/api/gateway/beta-status
docker stop agent-awesome-cloudflare-debug
```

The automated release E2E suite builds this image, runs it against a mock LLM
provider, launches the Flutter desktop UI, and verifies a chat round trip:

```sh
./e2e/run-release-e2e.sh
```

Run these commands from the repository root:

```sh
nvm use
npm --prefix deploy/cloudflare/worker install --cache ../../build/npm-cache
npm run cloudflare:test
npm run cloudflare:r2:create
npm --prefix deploy/cloudflare/worker exec wrangler secret put AGENTAWESOME_GATEWAY_TOKEN
npm --prefix deploy/cloudflare/worker exec wrangler secret put AGENTAWESOME_PERSISTENCE_TOKEN
npm --prefix deploy/cloudflare/worker exec wrangler secret put OPENAI_API_KEY
npm run cloudflare:deploy
```

From `deploy/cloudflare/worker`, use the shorter package-local commands:
`npm test`, `npx wrangler secret put ...`, and `npm run deploy`.
Do not pass the repository-root config path after `cd deploy/cloudflare/worker`;
`--config deploy/cloudflare/worker/wrangler.jsonc` resolves to a duplicated
`deploy/cloudflare/worker/deploy/cloudflare/worker/wrangler.jsonc` path.
The package deploy scripts run Wrangler from the Worker directory and keep
Wrangler/Docker state under `build/`, which avoids read-only home-directory
failures in constrained environments.

The R2 bucket command requires a Cloudflare API token or OAuth session with
`Workers R2 Storage Write`. If Wrangler asks for `CLOUDFLARE_API_TOKEN`, create a
temporary token with that permission, export it for the command, then unset it.

After the first deployment, wait for the container application to finish
provisioning. When Slack is enabled, set the Slack app Event Request URL to:

```text
https://agent-awesome.com/slack/events
```

Use the same Slack bot token and signing secret you tested locally. Upload
`SLACK_SIGNING_SECRET` and `SLACK_BOT_TOKEN` before setting `SLACK_ENABLED=true`.
Do not set `SLACK_APP_TOKEN` for this deployment unless you deliberately switch
the cloud config back to Socket Mode.

The public `workers.dev` URL is disabled. `agent-awesome.com/*` is the configured
Cloudflare Worker route for the existing domain. The Worker forwards bearer-authenticated
gateway control-plane requests. Slack is disabled by default; enabling it trusts
Slack-signed events from the installed app and routes accepted messages to the
default `doug` profile. Add profile bindings or legacy allow-list values only
when you need narrower routing.

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

For multi-profile Slack, put `slack_bindings` on the relevant objects inside
`AGENTAWESOME_AGENT_PROFILES_JSON`. A binding includes `team_id`, `channel_id`,
and `allowed_user_ids`. The older single-channel `SLACK_ALLOWED_TEAM_ID`,
`SLACK_ALLOWED_USER_ID`, and `SLACK_ALLOWED_CHANNEL_ID` values still scope Slack
to the default profile, but they do not select between Doug and Family.

## Persistence Note

The bundled memory database lives under `/app/data` inside the container. This
is enough for an HTTP pilot while the container stays alive, but Cloudflare
Container disk is ephemeral after the instance sleeps. The checked-in Worker
config points at a beta sandbox R2 bucket; use provisioner-generated per-agent
buckets for tester deployments and keep personal memory buckets out of the beta
path.
