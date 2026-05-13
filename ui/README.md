# Agent Awesome UI

A desktop-first Flutter app for the Agent Awesome workspace.

## Run

Run the UI. On startup it loads a runtime profile, checks the harness and MCP
servers in that profile, and starts any missing services it owns:

```sh
flutter run -d linux
```

The default profile uses the real local services and harness configuration:

- `memoryd` on `127.0.0.1:8090`, serving memory and graph-backed task tools
- the harness web API on `127.0.0.1:8080`

The harness uses `../harness/model.yaml`, so it needs the configured provider
credential, such as `OPENAI_API_KEY`, in the environment or Agent Awesome
keyring before chat runs can connect.

Runtime profiles are JSON service topologies. The default shipped profile is
`runtime_profiles/agent_awesome.json`; the app loads that file when no
profile path is supplied. A profile can point the harness at different model,
agent, and tool config files, and can point memory and task surfaces at the
same graph-backed MCP endpoint. Managed servers include `working_directory`,
`package_path`, and `arguments`; external servers set `auto_start` to `false`.

```sh
flutter run -d linux --dart-define=AGENTAWESOME_RUNTIME_PROFILE=/home/doug/dev/agentawesome/ui/runtime_profiles/agent_awesome.json
```

The UI reads these optional `--dart-define` values:

- `AGENT_API_BASE_URL`, default `http://127.0.0.1:8080/api`
- `AGENT_GATEWAY_BASE_URL`, default `http://127.0.0.1:8070/api`
- `MEMORY_MCP_URL`, default `http://127.0.0.1:8090/mcp`
- `AGENT_APP_NAME`, default `agent_awesome`
- `AGENT_USER_ID`, default `doug`
- `AGENTAWESOME_WORKSPACE_ROOT`, default `/home/doug/dev/agentawesome/agent`
- `AUTO_START_LOCAL_SERVICES`, default `true`
- `AGENTAWESOME_RUNTIME_PROFILE`, default empty, which loads
  `runtime_profiles/agent_awesome.json`

The Linux release build also reads those values from the process environment,
so one downloaded binary can point at either a local or hosted gateway.

When services are unavailable, the app marks the relevant connections as
disconnected and shows empty states.

## Gateway Mode

The default Agent Awesome profile starts memory, the harness, and
`agent-gateway`. The UI sends assistant traffic through the gateway while the
gateway forwards to the harness. To override the gateway endpoint:

```sh
flutter run -d linux \
  --dart-define=AGENT_GATEWAY_BASE_URL=http://127.0.0.1:8070/api
```

## Context Profiles

The UI talks to the gateway context API for memory and task surfaces. The
harness owns MCP tool invocation, and the gateway adapts harness context
responses for the UI.

- `runtime_profiles/local_dev.json` starts local memory and points the harness
  at `harness/tool.local.yaml`.
- `runtime_profiles/cloudflare_context.json` points the desktop UI at a hosted
  Cloudflare gateway. It does not start local harness, gateway, or memory
  binaries.

For the Cloudflare profile, set `AGENT_GATEWAY_BASE_URL`,
`AGENTAWESOME_GATEWAY_TOKEN`, and `AGENTAWESOME_RUNTIME_PROFILE` before starting
the release binary. The UI sends chat, memory, and task requests through that
gateway.
