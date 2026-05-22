# E2E Suites

This directory contains repository-level integration tests that exercise local
Agent Awesome behavior without release or hosting assets.

## Codex Pilot

The Codex pilot suite runs a deterministic workflow through the local harness
and validates the generated state.

```sh
cd e2e/codexpilot
AGENTAWESOME_RUN_CODEX_PILOT_E2E=1 go test -run TestCodexCLIPilotWorkflowEndToEnd -count=1 ./...
```

Diagnostics and temporary outputs belong under `build/e2e` when a suite needs
to persist logs or captures.
