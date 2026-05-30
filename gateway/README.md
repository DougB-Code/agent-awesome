# Agent Gateway

`agent-gateway` is the personal-grade cloud/local command plane for Agent
Awesome. It is a small Go HTTP service that can run as a normal static binary,
proxy Flutter chat traffic to the harness, and optionally start sibling harness
and memory binaries for local desktop-style deployments.

## Run Locally

Start the existing harness and memory processes separately, then run:

```sh
go run ./cmd/agent-gateway
```

Point the Flutter UI at the gateway instead of the harness:

```sh
flutter run -d linux \
  --dart-define=AGENT_GATEWAY_BASE_URL=http://127.0.0.1:8070/api
```

The default UI runtime topology can start memory, the harness, and the gateway
for development pilots. Use `AUTO_START_LOCAL_SERVICES=false` only when an outer
launcher or cloud process manager owns those binaries.

## Local Launcher Mode

The gateway can also start sibling binaries when the configured health checks
are not reachable. Arguments are repeatable so callers do not need a shell. For
the current local/server migration shape, prefer `--harness-embedded-services`:
the gateway starts only the harness plus memory domains. The harness hosts the
workflow endpoint in-process, while command tools are wired directly into ADK
without a command MCP loopback or embedded MCP-manager listener.

```sh
go run ./cmd/agent-gateway \
  --harness-embedded-services \
  --harness-auto-start \
  --harness-command /path/to/agent-awesome \
  --harness-workdir /home/doug/dev/agentawesome/agent/harness \
  --harness-arg run \
  --harness-arg --model \
  --harness-arg /path/to/model.yaml \
  --harness-arg --agent \
  --harness-arg /path/to/agent.yaml \
  --harness-arg --tool \
  --harness-arg /path/to/tool.yaml \
  --harness-arg -- \
  --harness-arg web \
  --harness-arg --port \
  --harness-arg 8080 \
  --harness-arg api \
  --memory-auto-start \
  --memory-command /path/to/memoryd \
  --memory-arg --addr \
  --memory-arg 127.0.0.1:8090
```

When `--harness-embedded-services` is enabled, do not also configure
`--workflow-auto-start` or `--workflow-command`; those would create competing
process owners. The gateway still checks the workflow health URL, but the
listener is owned by the harness process.

For packaged pilots, the same values can be supplied with environment variables:

- `AGENTAWESOME_GATEWAY_ADDR`
- `AGENTAWESOME_HARNESS_API_BASE_URL`
- `AGENTAWESOME_CONTEXT_API_BASE_URL`
- `AGENTAWESOME_CONTEXT_API_TOKEN`
- `AGENTAWESOME_MEMORY_MCP_URL`
- `AGENTAWESOME_MEMORY_DOMAINS_JSON`
- `AGENTAWESOME_AGENT_PROFILES_JSON`
- `AGENTAWESOME_MEMORY_SERVICES_JSON`
- `AGENTAWESOME_GATEWAY_TOKEN`
- `AGENTAWESOME_ALLOWED_ORIGIN`
- `AGENTAWESOME_ALLOW_UNAUTHENTICATED_LOOPBACK_ONLY`
- `AGENTAWESOME_RUNTIME_POLICY_TEXT`
- `AGENTAWESOME_HARNESS_EMBEDDED_SERVICES`
- `AGENTAWESOME_HARNESS_AUTO_START`
- `AGENTAWESOME_HARNESS_COMMAND`
- `AGENTAWESOME_HARNESS_ARGS`, as a JSON string array
- `AGENTAWESOME_MEMORY_AUTO_START`
- `AGENTAWESOME_MEMORY_COMMAND`
- `AGENTAWESOME_MEMORY_ARGS`, as a JSON string array
- `SLACK_ENABLED`
- `SLACK_SOCKET_MODE`
- `SLACK_SIGNING_SECRET`
- `SLACK_BOT_TOKEN`
- `SLACK_APP_TOKEN`
- `SLACK_ALLOWED_TEAM_ID`
- `SLACK_ALLOWED_USER_ID`
- `SLACK_ALLOWED_CHANNEL_ID`

The gateway may run without `AGENTAWESOME_GATEWAY_TOKEN` only when it listens on
a loopback address such as `127.0.0.1:8070` or `localhost:8070`. Non-loopback
binds such as `0.0.0.0:8070` and `:8070` require `AGENTAWESOME_GATEWAY_TOKEN`
or `--auth-token`. Non-local `AGENTAWESOME_ALLOWED_ORIGIN` values also require
the gateway token. Set `AGENTAWESOME_ALLOW_UNAUTHENTICATED_LOOPBACK_ONLY=false`
when you want to force bearer auth even for local loopback development.

The harness context API should normally be reached through gateway
`/api/context/*` routes only. Keep the harness context listener on loopback; if
it must bind outside loopback, set the same `AGENTAWESOME_CONTEXT_API_TOKEN` on
the harness and gateway, or pass `--context-api-token` to both.

## Slack Pilot

For local testing, enable Slack Socket Mode so Slack does not need a public
Request URL:

```sh
SLACK_ENABLED=true \
SLACK_SOCKET_MODE=true \
SLACK_APP_TOKEN=xapp-... \
SLACK_BOT_TOKEN=xoxb-... \
go run ./cmd/agent-gateway
```

The Slack app needs Socket Mode enabled, an app-level token with
`connections:write`, a bot token with `chat:write`, and message event
subscriptions such as `message.channels` for channel pilots. Slack startup
trusts Slack-signed events from the installed app by default. Add a complete
team/user/channel allow-list for the default profile, or profile-specific
`slack_bindings` inside `AGENTAWESOME_AGENT_PROFILES_JSON`, when you need
narrower routing.
Use profile bindings when one gateway serves more than one profile; the adapter
selects the profile before it calls `/api/*`.

For cloud deployments, turn Socket Mode off and configure Slack's Events API
Request URL to:

```text
https://<gateway-host>/slack/events
```

Then provide `SLACK_SIGNING_SECRET` so the gateway can verify Slack's HTTP
request signatures before accepting events.

## API Surface

- `GET /healthz` reports gateway liveness.
- `GET /api/gateway/status` reports sanitized gateway and dependency status.
- `GET /api/gateway/channels` lists active and planned channel adapters.
- `POST /slack/events` receives Slack Events API webhooks.
- `POST /mcp` proxies UI-facing memory MCP traffic to the configured memory service.
- `/api/context/*` proxies harness context tool traffic.
- `/api/*` proxies assistant API traffic to the configured harness.

`GET /api/gateway/status` includes dependency readiness. While supervised
dependencies are still starting or failed, `/api/*`, `/api/context/*`, and
`/mcp` return `503 dependency not ready` instead of leaking upstream connection
errors. `GET /healthz` stays live for process liveness.

`POST /api/run_sse` forwards user text unchanged by default. Operators can set
`AGENTAWESOME_RUNTIME_POLICY_TEXT` for explicit deployment-specific guidance,
but stable tool-call behavior lives in harness agent instructions and runtime
callbacks instead of gateway prompt text.

Gateway proxy request bodies are capped at 8 MiB. Oversized bodies return
`413 Payload Too Large`.
