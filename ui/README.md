# Agent Awesome UI

A desktop-first Flutter app for the Agent Awesome workspace.

## Run

Build the local service binaries once before launching the UI:

```sh
cd /home/doug/dev/agentawesome/agent
./scripts/dev.sh build
```

Run the UI. On startup it loads the service topology, checks the harness and
MCP servers in that topology, and starts any missing services it owns:

```sh
./scripts/dev.sh ui
```

To build the runtime services and launch the UI with one command:

```sh
./scripts/dev.sh run
```

The default topology uses the real local services and harness configuration:

- `memoryd` on `127.0.0.1:8090`, serving memory and graph-backed task tools
- the harness web API on `127.0.0.1:8080`

The harness uses `../harness/model.yaml`, so it needs the configured provider
credential, such as `OPENAI_API_KEY`, in the environment or Agent Awesome
keyring before chat runs can connect.

Runtime topology JSON describes service wiring. The shipped topology is
`runtime_topology/agent_awesome.json`, and the app copies it into managed app
storage on first launch.

The UI reads these optional `--dart-define` values:

- `AGENT_API_BASE_URL`, default `http://127.0.0.1:8080/api`
- `AGENT_GATEWAY_BASE_URL`, default `http://127.0.0.1:8070/api`
- `MEMORY_MCP_URL`, default `http://127.0.0.1:8090/mcp`
- `AGENT_APP_NAME`, default `agent_awesome`
- `AGENT_USER_ID`, default `doug`
- `AGENTAWESOME_WORKSPACE_ROOT`, default `/home/doug/dev/agentawesome/agent`
- `AUTO_START_LOCAL_SERVICES`, default `true`

The Linux release build also reads those values from the process environment,
so one downloaded binary can point at either a local or hosted gateway.

When services are unavailable, the app marks the relevant connections as
disconnected and shows empty states.

## Gateway Mode

The default Agent Awesome topology starts memory, the harness, and
`agent-gateway`. The UI sends assistant traffic through the gateway while the
gateway forwards to the harness. To override the gateway endpoint:

```sh
flutter run -d linux \
  --dart-define=AGENT_GATEWAY_BASE_URL=http://127.0.0.1:8070/api
```

## Context Runtime

The UI talks to the gateway context API for memory and task surfaces. The
harness owns MCP tool invocation, and the gateway adapts harness context
responses for the UI.
