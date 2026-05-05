# Agent Awesome UI

A desktop-first Flutter app for the Aurora personal assistant workspace.

## Run

Run the UI. On startup it loads a runtime profile, checks the harness and MCP
servers in that profile, and starts any missing services it owns:

```sh
flutter run -d linux
```

The default profile uses the real services and pilot configuration:

- `memoryd` on `127.0.0.1:8090`, serving memory and graph-backed task tools
- the harness web API on `127.0.0.1:8080`

Memory and task data live under
`../harness/build/pilot/personal-assistant/data/`. The harness uses the
personal-assistant pilot model config, so it needs the configured provider
credential, such as `OPENAI_API_KEY`, in the environment or Agent Awesome
keyring before chat runs can connect.

Runtime profiles are JSON service topologies. The default shipped profile is
`runtime_profiles/personal_assistant.json`; the app loads that file when no
profile path is supplied. A profile can point the harness at different model,
agent, and tool config files, and can point memory and task surfaces at the
same graph-backed MCP endpoint. Managed servers include `working_directory`,
`package_path`, and `arguments`; external servers set `auto_start` to `false`.

```sh
flutter run -d linux --dart-define=AGENTAWESOME_RUNTIME_PROFILE=/home/doug/dev/agentawesome/ui/runtime_profiles/personal_assistant.json
```

The UI reads these optional `--dart-define` values:

- `AGENT_API_BASE_URL`, default `http://127.0.0.1:8080/api`
- `MEMORY_MCP_URL`, default `http://127.0.0.1:8090/mcp`
- `AGENT_APP_NAME`, default `personal_pilot`
- `AGENT_USER_ID`, default `doug`
- `AGENTAWESOME_WORKSPACE_ROOT`, default `/home/doug/dev/agentawesome`
- `AUTO_START_LOCAL_SERVICES`, default `true`
- `AGENTAWESOME_RUNTIME_PROFILE`, default empty, which loads
  `runtime_profiles/personal_assistant.json`

When services are unavailable, the app marks the relevant connections as
disconnected and shows empty states.
