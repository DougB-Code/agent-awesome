# TODO

## Beta Validation

- Run a clean Linux release smoke on a machine or VM with no Go toolchain on `PATH`.
- Run a live Cloudflare beta smoke: health, gateway status, beta status, Slack allow-list reply, memory write/search, and `/internal/context-snapshot/memory` restore/save.
- Prove a second Cloudflare memory domain once before inviting beta users: separate port, health row, service status, and R2 snapshot object.

## Post-Beta Backlog

- The app background should match panel backgrounds instead of rendering black.
- Add a batch job to organize memory and ask follow-up questions when an item needs more detail.
- Integrate/sync with Apple, Gmail, and Outlook calendars through external plugin architecture.
- Integrate Codex, Claude Code, Gemini, and Copilot CLIs as tools. Cloud login and credential management may require server deployments.
- Integrate server provisioning and hardening as tools.
- Run cleanup passes to eliminate excess logic and duplicate implementations.

- Remove the refresh button from files and people. It should just reload automatically. 