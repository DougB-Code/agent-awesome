# User Provisioning Implementation Plan

This plan moves Agent Awesome from a developer-operated single pilot to a smooth
consumer onboarding flow where each user gets an isolated cloud agent. The
default product model is managed Agent Awesome cloud. Bring-your-own Cloudflare
can remain an advanced option later.

## Principles

- Users should not handle infrastructure environment variables.
- Cloudflare setup is platform infrastructure, not end-user onboarding.
- Slack is optional and should be connected through OAuth, not pasted tokens.
- User memory is isolated by default. Shared project memory is out of scope.
- Provisioning must be idempotent: repeated runs repair drift instead of
  rotating secrets or duplicating resources.
- Desktop-distributed setup tooling must be written in Go.

## Target User Experience

Initial operator-driven pilot:

```sh
agent-awesome-provision cloudflare apply --agent-id sister
```

Target consumer flow:

1. User signs in or accepts an invite.
2. Agent Awesome automatically provisions a private cloud agent.
3. User opens the desktop app and chats.
4. User optionally clicks **Connect Slack**.
5. Slack OAuth completes setup without exposing bot tokens or signing secrets.

## Platform Infrastructure

Create a dedicated platform project, separate from the app repo:

```text
agent-awesome-cloud/
  worker/
  container/
  infra/
  docs/
```

The platform project owns:

- Cloudflare account and zone configuration.
- `agent-awesome.com` routing and wildcard DNS, such as
  `*.agent-awesome.com`.
- Base Worker and Container source.
- Cloudflare Container build/deploy strategy.
- Platform-level R2, Worker, and Durable Object policy.
- Distributed Slack app credentials.
- Platform-level secrets and release automation.

The desktop/provisioning binary owns:

- Creating one cloud agent for one user.
- Creating a dedicated R2 bucket for that user.
- Creating or reusing per-agent internal tokens.
- Deploying or reconciling that user agent.
- Health-checking the deployed gateway.
- Connecting optional integrations.

## Resource Model

Each provisioned user receives isolated cloud resources:

```text
agent_id: stable opaque id, e.g. sister
worker: agent-awesome-sister
hostname: sister.agent-awesome.com
r2_bucket: agent-awesome-sister-memory
snapshot_key: context-snapshot.tar.gz
gateway_token: generated internal token
persistence_token: generated internal token
slack_installation: optional
```

Use a dedicated R2 bucket per user. R2 pricing is based on storage and
operations, not bucket count, and the security model is simpler than a shared
bucket with per-user prefixes.

## Phase 1: Operator Provisioning Baseline

Goal: provision a user cloud agent from your machine with a Go binary.

Status: implemented for non-destructive provisioning and inspection.

Implemented:

- `provision/` Go module.
- `cloudflare render` command for per-agent Cloudflare artifacts.
- `cloudflare apply` command that can:
  - render desired Wrangler config,
  - create a dedicated R2 bucket,
  - set Worker secrets through Wrangler,
  - deploy the Worker/Container,
  - health-check `/api/gateway/status`.
- Stable generated internal tokens stored in the OS keyring.
- Non-secret provisioning records stored under the Agent Awesome config dir.
- Configurable memory snapshot key in the Worker.
- Platform config file support so flags are not repeated.
- `agent list` and `agent status`.
- Credential commands for external secrets.

Remaining:

- Add `agent delete` with explicit confirmation and Cloudflare cleanup.
- Add stronger live apply output and failure diagnostics.
- Replace direct Slack secret entry with Slack OAuth in Phase 4.

Operator prerequisites:

- A Cloudflare account with access to the managed Agent Awesome zone.
- A Cloudflare API token stored with `credentials set CLOUDFLARE_API_TOKEN`.
- The Cloudflare account id stored in platform config.
- Docker available for Cloudflare Container image builds.
- Node/npm available so the provisioner can run `npx wrangler`.
- `OPENAI_API_KEY` stored with `credentials set` or exported in the shell.
- Optional Slack bot token and signing secret only when using `--slack`.

First-time operator setup:

```sh
agent-awesome-provision platform init --zone-name agent-awesome.com --cloudflare-account-id <account-id>
agent-awesome-provision credentials set CLOUDFLARE_API_TOKEN
agent-awesome-provision credentials set OPENAI_API_KEY
agent-awesome-provision cloudflare apply --agent-id sister
agent-awesome-provision agent status sister
```

Acceptance criteria:

- Running `cloudflare apply --agent-id sister` twice reuses the same internal
  tokens.
- Sister gets a dedicated R2 bucket.
- Gateway health reports `harness` and `memory` as connected.
- Generated artifacts contain no secret values.

## Phase 2: Cleanup And Diagnostics UX

Goal: make the provisioner feel like an operator tool instead of a collection of
flags and environment variables.

Status: implemented for Wrangler-based cleanup and operator diagnostics.

Implemented:

```sh
agent-awesome-provision agent delete sister
```

- Live apply progress output for each reconciliation step.
- Live delete progress output for Worker, snapshot object, and R2 bucket cleanup.
- Dry-run delete plans before destructive work.
- Exact agent-id confirmation before destructive deletion.
- `--force` support for non-interactive operator automation.
- `--local-only` cleanup for removing local records and generated tokens.
- Error messages that explain common missing Cloudflare permissions or
  prerequisites.
- Interactive credential prompts that do not echo typed values.

Remaining:

- Add deeper R2 cleanup when a bucket contains more than the known memory
  snapshot object.

Platform config should include:

```json
{
  "cloudflare_account_id": "...",
  "zone_name": "agent-awesome.com",
  "agent_hostname_suffix": "agent-awesome.com",
  "worker_source_dir": "...",
  "default_model_provider": "openai"
}
```

Credential lookup order:

1. OS keyring.
2. Environment variable.
3. Interactive prompt when running in a terminal.

Acceptance criteria:

- `apply --agent-id sister` can infer hostname, zone, repo paths, and output
  directory from platform config.
- `OPENAI_API_KEY` no longer needs to be exported in the shell.
- `agent status sister` can health-check the deployed agent using the stored
  gateway token.
- `agent delete sister` requires confirmation before destructive Cloudflare or
  R2 deletion.
- `agent delete sister --dry-run` lists the Cloudflare cleanup commands without
  deleting remote resources or local state.

## Phase 3: Cloudflare Reconciliation

Goal: reduce reliance on Wrangler where direct Cloudflare APIs are practical.

Status: implemented for R2 reconciliation, Worker secret upload, route/DNS
preflight, route repair, and operator dashboard links. Wrangler still owns
Container build/deploy.

Implemented:

- R2 bucket create/list/delete.
- R2 snapshot object delete through Wrangler during cleanup.
- Worker secret set/delete API methods.
- First-time Worker bootstrap before direct secret upload.
- Worker secret upload through direct API during apply after bootstrap.
- Worker route validation.
- Worker route create/update repair after deploy.
- Worker route cleanup during delete.
- DNS readiness checks.
- Deployment dashboard and log links.
- Cloudflare API token injection into Wrangler commands.
- Structured JSON output for apply, delete, list, and status commands.

Keep Wrangler temporarily for Container deployment if Cloudflare Containers still
require Wrangler for image build/push/deploy.

Remaining:

- Keep Wrangler only for Container build/deploy until Cloudflare Containers have
  a practical direct API path for image build and rollout from this binary.

Acceptance criteria:

- Provisioner can detect existing buckets and routes before attempting create.
- Bucket creation is idempotent and does not treat “already exists” as failure.
- Errors explain the missing Cloudflare permission or resource.
- Live apply has a clear reconciliation summary.
- `--json` output is available for automation consumers.

## Phase 4: Slack OAuth Integration

Goal: remove pasted Slack bot tokens and signing secrets from user setup.

Platform owns:

```text
SLACK_CLIENT_ID
SLACK_CLIENT_SECRET
SLACK_SIGNING_SECRET
```

User flow:

1. User clicks **Connect Slack** in the desktop app.
2. Desktop opens Slack OAuth authorization URL.
3. Slack redirects to Agent Awesome cloud callback.
4. Agent Awesome exchanges the code for a bot token.
5. Agent Awesome stores the Slack installation for the user agent.
6. Slack Events API routes incoming events to the correct agent.

Required storage:

```text
team_id -> agent_id
bot_token -> encrypted cloud secret
installed_by_user_id
scopes
created_at
updated_at
```

Start with minimal scopes:

```text
app_mentions:read
im:history
im:read
chat:write
```

Add slash commands, files, canvases, and broader channel access later as
optional permissions.

Acceptance criteria:

- User never sees `SLACK_BOT_TOKEN`.
- User never sees `SLACK_SIGNING_SECRET`.
- Slack can be connected after the cloud agent already exists.
- Disconnecting Slack revokes or deletes the installation token.

## Phase 5: Desktop App Onboarding

Goal: move from operator command to desktop-initiated provisioning.

Implement desktop-facing Go flows:

- User identity bootstrap.
- Cloud agent create request.
- Cloud agent status polling.
- Local profile creation that points to the cloud gateway.
- Optional Slack connect action.
- Error recovery and retry.

The desktop app should show product concepts, not infrastructure:

```text
Creating your cloud agent...
Starting memory...
Connecting chat...
Ready.
```

Do not show:

```text
R2 bucket
Wrangler
Worker binding
AGENTAWESOME_PERSISTENCE_TOKEN
```

Acceptance criteria:

- A non-technical user can complete setup without copying secrets.
- Failed provisioning can be retried safely.
- The local app can reconnect to an existing cloud agent after reinstall.

## Phase 6: Release And Operations

Goal: make this safe to publish.

Implement:

- Cross-platform Go binary builds.
- Version command.
- Checksums.
- Smoke tests for provisioner commands.
- Cloudflare platform bootstrap docs.
- Backup/export command for user memory.
- Delete-account path with memory deletion.
- Basic audit logs for provisioning actions.
- Operational runbook for failed deployments.

Acceptance criteria:

- A clean machine can install the binary and provision a test agent using only
  documented prerequisites.
- Platform infra can be recreated from the dedicated cloud project.
- Provisioning failures produce actionable messages.
- User memory can be exported before deletion.

## Near-Term Checklist For Sister Pilot

- Create dedicated platform project.
- Ensure wildcard DNS for provisioned agents.
- Add platform config support.
- Add `agent status` command.
- Add keyring-backed `OPENAI_API_KEY` credential lookup.
- Provision `sister.agent-awesome.com`.
- Keep Slack disabled initially unless needed.
- Verify cloud chat from the local desktop app.
- Add Slack OAuth only after base cloud agent provisioning is reliable.
