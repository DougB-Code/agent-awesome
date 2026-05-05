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

The default UI runtime profile can start memory, the harness, and the gateway
for development pilots. Use `AUTO_START_LOCAL_SERVICES=false` only when an outer
launcher or cloud process manager owns those binaries.

## Local Launcher Mode

The gateway can also start sibling binaries when the configured health checks
are not reachable. Arguments are repeatable so callers do not need a shell.

```sh
go run ./cmd/agent-gateway \
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

For packaged pilots, the same values can be supplied with environment variables:

- `AGENTAWESOME_GATEWAY_ADDR`
- `AGENTAWESOME_HARNESS_API_BASE_URL`
- `AGENTAWESOME_MEMORY_MCP_URL`
- `AGENTAWESOME_GATEWAY_TOKEN`
- `AGENTAWESOME_HARNESS_AUTO_START`
- `AGENTAWESOME_HARNESS_COMMAND`
- `AGENTAWESOME_HARNESS_ARGS`, as a JSON string array
- `AGENTAWESOME_MEMORY_AUTO_START`
- `AGENTAWESOME_MEMORY_COMMAND`
- `AGENTAWESOME_MEMORY_ARGS`, as a JSON string array

## API Surface

- `GET /healthz` reports gateway liveness.
- `GET /api/gateway/status` reports sanitized gateway and dependency status.
- `GET /api/gateway/channels` lists active and planned channel adapters.
- `/api/*` proxies ADK-compatible API traffic to the configured harness.

`POST /api/run_sse` receives server-owned runtime policy injection before the
request is forwarded. This lets local and cloud deployments enforce the same
task-writing behavior without making Slack, SMS, email, or Flutter own agent
policy.
