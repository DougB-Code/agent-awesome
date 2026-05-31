#!/usr/bin/env bash
# Builds and probes a generated Docker runtime bundle through gateway routes.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_CONFIG="${DOCKER_CONFIG:-"$ROOT_DIR/build/docker-config"}"
BUNDLE_ID="${BUNDLE_ID:-smoke}"
BUNDLE_DIR="$ROOT_DIR/build/remote-runtime/$BUNDLE_ID"
IMAGE_TAG="${IMAGE_TAG:-agent-awesome/remote-runtime:smoke}"
CONTAINER_NAME="${CONTAINER_NAME:-agent-awesome-smoke-$$}"
HOST_PORT="${HOST_PORT:-18070}"
GATEWAY_TOKEN="${AGENTAWESOME_GATEWAY_TOKEN:-smoke-token}"
PROFILE_ID="${AA_PROFILE_ID:-personal}"
APP_NAME="${AA_APP_NAME:-Agent Awesome}"
USER_ID="${AA_USER_ID:-doug}"
BASE_URL="http://127.0.0.1:$HOST_PORT"
HARNESS_PORT="${AA_HARNESS_PORT:-18081}"
CONTEXT_PORT="${AA_CONTEXT_PORT:-18082}"
RUNBOOK_PORT="${AA_RUNBOOK_PORT:-18083}"
MEMORY_PORT="${AA_MEMORY_PORT:-18084}"
RUN_UI_REMOTE_SMOKE="${RUN_UI_REMOTE_SMOKE:-0}"
RUN_UI_REMOTE_MODEL_CHAT="${RUN_UI_REMOTE_MODEL_CHAT:-0}"
UI_RUNTIME_PROFILE="${UI_RUNTIME_PROFILE:-"$BUNDLE_DIR/ui-runtime.remote-gateway.json"}"
LOCAL_GEMMA_MODEL_PATH="${AA_LOCAL_GEMMA_MODEL:-${LOCAL_GEMMA_MODEL_PATH:-}}"
LOCAL_LLAMA_SERVER_PATH="${AA_LLAMA_SERVER_LOCAL:-${LOCAL_LLAMA_SERVER_PATH:-}}"
REMOTE_MODEL_CHAT_URL="${AA_LOCAL_MODEL_CHAT_URL:-}"
DOCKER_HOST_GATEWAY="${AA_DOCKER_HOST_GATEWAY:-0}"
DOCKER_HOST_NETWORK="${AA_DOCKER_HOST_NETWORK:-0}"

# Prints a status line for the smoke run.
log() {
  printf '[remote-runtime-smoke] %s\n' "$*"
}

# Fails when a required command is unavailable.
require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$name" >&2
    exit 127
  fi
}

# Writes the generated bundle fixture used for the smoke image.
write_bundle() {
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR/config/bin" "$BUNDLE_DIR/config/runbooks"
  if [ -n "$LOCAL_LLAMA_SERVER_PATH" ]; then
    mkdir -p "$BUNDLE_DIR/config/bin"
    cp "$LOCAL_LLAMA_SERVER_PATH" "$BUNDLE_DIR/config/bin/"
  fi
  cp "$ROOT_DIR/harness/agent.yaml" "$BUNDLE_DIR/config/agent.yaml"
  cp "$ROOT_DIR/harness/tool.local.yaml" "$BUNDLE_DIR/config/tool.yaml"
  cp "$ROOT_DIR/deploy/docker/config/model.local-gemma.yaml" \
    "$BUNDLE_DIR/config/model.yaml"
  cat >"$BUNDLE_DIR/config/runbooks/smoke_noop.yaml" <<'YAML'
apiVersion: aa.runbook/v1
kind: state_machine
id: smoke_noop
name: Smoke Noop
initial: start
states:
  - id: start
YAML
  cat >"$BUNDLE_DIR/Dockerfile" <<DOCKERFILE
# Builds a configured Agent Awesome remote runtime smoke image.
FROM golang:1.26-bookworm AS build

WORKDIR /src

COPY platform ./platform
COPY harness ./harness
COPY gateway ./gateway
COPY memory ./memory

RUN cd harness && go build -trimpath -buildvcs=false -o /out/agent-awesome ./cmd/agent-awesome
RUN cd harness && go build -trimpath -buildvcs=false -o /out/runbook-service ./cmd/runbook-service
RUN cd gateway && go build -trimpath -buildvcs=false -o /out/agent-gateway ./cmd/agent-gateway
RUN cd memory && go build -trimpath -buildvcs=false -o /out/memoryd ./cmd/memoryd

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agent-awesome

COPY --from=build /out/agent-awesome /usr/local/bin/agent-awesome
COPY --from=build /out/runbook-service /usr/local/bin/runbook-service
COPY --from=build /out/agent-gateway /usr/local/bin/agent-gateway
COPY --from=build /out/memoryd /usr/local/bin/memoryd
COPY build/remote-runtime/$BUNDLE_ID/config/agent.yaml /opt/agent-awesome/config/agent.yaml
COPY build/remote-runtime/$BUNDLE_ID/config/tool.yaml /opt/agent-awesome/config/tool.yaml
COPY build/remote-runtime/$BUNDLE_ID/config/model.yaml /opt/agent-awesome/config/model.yaml
COPY build/remote-runtime/$BUNDLE_ID/config/runbooks /opt/agent-awesome/config/runbooks
COPY build/remote-runtime/$BUNDLE_ID/config/bin /opt/agent-awesome/bin
COPY deploy/docker/entrypoint.sh /usr/local/bin/agent-awesome-container

RUN chmod +x /usr/local/bin/agent-awesome-container \
    && if [ -d /opt/agent-awesome/bin ]; then find /opt/agent-awesome/bin -type f -exec chmod +x {} \;; fi \
    && mkdir -p /var/lib/agent-awesome /var/log/agent-awesome

EXPOSE 8070

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:8070/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agent-awesome-container"]
DOCKERFILE
}

# Writes a remote gateway runtime profile for the Flutter live smoke test.
write_ui_runtime_profile() {
  cat >"$UI_RUNTIME_PROFILE" <<JSON
{
  "id": "remote-smoke",
  "label": "Remote Smoke",
  "harness": {
    "id": "remote-smoke-harness",
    "label": "Remote Harness",
    "api_base_url": "$BASE_URL/api",
    "context_api_base_url": "$BASE_URL/api/context",
    "app_name": "$APP_NAME",
    "user_id": "$USER_ID",
    "working_directory": "/opt/agent-awesome",
    "executable_path": "/usr/local/bin/agent-awesome",
    "model_config": "/opt/agent-awesome/config/model.yaml",
    "agent_config": "/opt/agent-awesome/config/agent.yaml",
    "tool_config": "/opt/agent-awesome/config/tool.yaml",
    "port": 8070,
    "auto_start": false
  },
  "gateway": {
    "id": "remote-smoke-gateway",
    "label": "Remote Gateway",
    "api_base_url": "$BASE_URL/api",
    "health_url": "$BASE_URL/healthz",
    "status_url": "$BASE_URL/api/gateway/status",
    "working_directory": "/opt/agent-awesome",
    "executable_path": "/usr/local/bin/agent-gateway",
    "harness_base_url": "$BASE_URL/api",
    "context_base_url": "$BASE_URL/api/context",
    "memory_mcp_url": "$BASE_URL/mcp",
    "app_name": "$APP_NAME",
    "user_id": "$USER_ID",
    "profile_id": "$PROFILE_ID",
    "auth_credential": "AGENTAWESOME_GATEWAY_TOKEN",
    "model_provider_id": "local-gemma",
    "model_id": "gemma",
    "port": 8070,
    "auto_start": false,
    "enabled": true
  },
  "runbook": {
    "id": "remote-smoke-runbook",
    "label": "Remote Runbook",
    "api_base_url": "$BASE_URL/api/runbooks",
    "health_url": "$BASE_URL/healthz",
    "hosted_by_harness": false,
    "working_directory": "",
    "executable_path": "",
    "definitions_dir": "",
    "db_path": "",
    "port": 8070,
    "auto_start": false,
    "enabled": true
  },
  "memory_domains": [
    {
      "id": "memory",
      "label": "Remote Memory",
      "kind": "memory",
      "endpoint": "$BASE_URL/mcp/memory",
      "health_url": "$BASE_URL/healthz",
      "working_directory": "",
      "executable_path": "",
      "db_path": "",
      "data_dir": "",
      "arguments": [],
      "auto_start": false,
      "enabled": true
    }
  ],
  "agent_memory": {
    "actor": "agent:$PROFILE_ID",
    "read_domains": ["memory"],
    "write_domains": ["memory"],
    "default_write_domain": "memory",
    "allowed_sensitivities": ["public", "internal", "private"]
  }
}
JSON
}

# Calls a protected gateway route.
gateway_curl() {
  curl -fsS \
    -H "Authorization: Bearer $GATEWAY_TOKEN" \
    -H "X-Agent-Awesome-Profile: $PROFILE_ID" \
    "$@"
}

# Calls a protected gateway JSON route.
gateway_json_curl() {
  curl -fsS \
    -H "Authorization: Bearer $GATEWAY_TOKEN" \
    -H "X-Agent-Awesome-Profile: $PROFILE_ID" \
    -H "Content-Type: application/json" \
    "$@"
}

# Stops the smoke container if it is still running.
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

# Prints container diagnostics when the smoke run fails.
finish() {
  local status="$?"
  if [ "$status" -ne 0 ]; then
    log "smoke failed; container logs follow"
    docker logs "$CONTAINER_NAME" >&2 || true
  fi
  cleanup
  exit "$status"
}

require_command docker
require_command curl
require_command jq
if [ "$RUN_UI_REMOTE_SMOKE" = "1" ]; then
  require_command flutter
fi
if [ "$RUN_UI_REMOTE_MODEL_CHAT" = "1" ]; then
  if [ -z "$LOCAL_GEMMA_MODEL_PATH" ] && [ -z "$REMOTE_MODEL_CHAT_URL" ]; then
    printf 'Set AA_LOCAL_GEMMA_MODEL or AA_LOCAL_MODEL_CHAT_URL for model chat smoke.\n' >&2
    exit 2
  fi
  if [ -n "$LOCAL_GEMMA_MODEL_PATH" ]; then
    if [ ! -f "$LOCAL_GEMMA_MODEL_PATH" ]; then
      printf 'Set AA_LOCAL_GEMMA_MODEL to a readable Gemma GGUF model path.\n' >&2
      exit 2
    fi
    if [ -z "$LOCAL_LLAMA_SERVER_PATH" ]; then
      LOCAL_LLAMA_SERVER_PATH="$(command -v llama-server || true)"
    fi
    if [ -z "$LOCAL_LLAMA_SERVER_PATH" ] || [ ! -f "$LOCAL_LLAMA_SERVER_PATH" ]; then
      printf 'Set AA_LLAMA_SERVER_LOCAL or install llama-server on PATH.\n' >&2
      exit 2
    fi
  fi
fi
mkdir -p "$DOCKER_CONFIG"
export DOCKER_CONFIG

write_bundle
log "building $IMAGE_TAG"
docker build -f "$BUNDLE_DIR/Dockerfile" -t "$IMAGE_TAG" "$ROOT_DIR"

cleanup
trap finish EXIT
log "starting $CONTAINER_NAME on $BASE_URL"
run_args=(
  run
  -d
  --rm
  --name "$CONTAINER_NAME"
  -e "AGENTAWESOME_GATEWAY_TOKEN=$GATEWAY_TOKEN"
  -e "AA_GATEWAY_PUBLIC_BASE_URL=$BASE_URL/api"
  -e "AA_PROFILE_ID=$PROFILE_ID"
  -e "AA_APP_NAME=$APP_NAME"
  -e "AA_USER_ID=$USER_ID"
)
if [ "$DOCKER_HOST_NETWORK" = "1" ]; then
  run_args+=(
    --network host
    -e "AA_GATEWAY_ADDR=127.0.0.1:$HOST_PORT"
    -e "AA_HARNESS_ADDR=127.0.0.1:$HARNESS_PORT"
    -e "AA_CONTEXT_ADDR=127.0.0.1:$CONTEXT_PORT"
    -e "AA_RUNBOOK_ADDR=127.0.0.1:$RUNBOOK_PORT"
    -e "AA_MEMORY_ADDR=127.0.0.1:$MEMORY_PORT"
  )
else
  run_args+=(-p "$HOST_PORT:8070")
fi
if [ "$DOCKER_HOST_GATEWAY" = "1" ]; then
  run_args+=(--add-host host.docker.internal:host-gateway)
fi
if [ -n "$REMOTE_MODEL_CHAT_URL" ]; then
  run_args+=(-e "AA_LOCAL_MODEL_CHAT_URL=$REMOTE_MODEL_CHAT_URL")
fi
if [ -n "$LOCAL_GEMMA_MODEL_PATH" ]; then
  run_args+=(
    -e "AA_LOCAL_MODEL_PATH=/models/$(basename "$LOCAL_GEMMA_MODEL_PATH")"
    -v "$(dirname "$LOCAL_GEMMA_MODEL_PATH"):/models:ro"
  )
fi
if [ -n "$LOCAL_LLAMA_SERVER_PATH" ]; then
  run_args+=(
    -e "AA_LLAMA_SERVER=/opt/agent-awesome/bin/$(basename "$LOCAL_LLAMA_SERVER_PATH")"
  )
fi
run_args+=("$IMAGE_TAG")
docker "${run_args[@]}" >/dev/null

ready=0
for _ in $(seq 1 80); do
  if gateway_curl "$BASE_URL/api/gateway/status" \
    | jq -e '.readiness.ready == true' >/dev/null; then
    ready=1
    break
  fi
  sleep 0.5
done
if [ "$ready" -ne 1 ]; then
  log "gateway did not become ready"
  exit 1
fi

log "checking assistant sessions route"
gateway_curl "$BASE_URL/api/apps/$APP_NAME/users/$USER_ID/sessions" \
  | jq -e '. == null or type == "array"' >/dev/null
log "checking runbook definitions route"
gateway_curl "$BASE_URL/api/runbooks/definitions" \
  | jq -e '.definitions[] | select(.id == "smoke_noop")' >/dev/null
log "checking memory MCP route"
gateway_json_curl \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  "$BASE_URL/mcp/memory" \
  | jq -e '.result.tools | length > 0' >/dev/null

log "creating Launchpad smoke launch"
launch_id="$(
  gateway_json_curl \
    -d '{"id":"smoke_noop_launch","name":"Smoke Noop Launch","runbook_id":"smoke_noop","defaults":{}}' \
    "$BASE_URL/api/launchpad" \
    | jq -r '.launch.id'
)"
log "previewing Launchpad smoke launch"
gateway_json_curl -d '{"input":{}}' "$BASE_URL/api/launchpad/$launch_id/preview" \
  | jq -e '.preview.status == "ready"' >/dev/null
log "starting Launchpad smoke launch"
run_id="$(
  gateway_json_curl -d '{"input":{}}' "$BASE_URL/api/launchpad/$launch_id/start" \
    | jq -r '.launch_run.run.id'
)"
log "checking Launchpad run snapshot"
gateway_curl "$BASE_URL/api/launchpad/runs/$run_id/snapshot" \
  | jq -e '.snapshot.run_id == "'"$run_id"'"' >/dev/null

if [ "$RUN_UI_REMOTE_SMOKE" = "1" ]; then
  log "running Flutter controller live smoke"
  write_ui_runtime_profile
  (
    cd "$ROOT_DIR/ui"
    RUN_AGENTAWESOME_REMOTE_LIVE_TEST=1 \
      AGENTAWESOME_REMOTE_LIVE_PROFILE="$UI_RUNTIME_PROFILE" \
      AGENT_GATEWAY_BASE_URL="$BASE_URL/api" \
      AGENTAWESOME_GATEWAY_TOKEN="$GATEWAY_TOKEN" \
      AGENT_APP_NAME="$APP_NAME" \
      AGENT_USER_ID="$USER_ID" \
      RUN_AGENTAWESOME_REMOTE_MODEL_CHAT="$RUN_UI_REMOTE_MODEL_CHAT" \
      AUTO_START_LOCAL_SERVICES=false \
      flutter test test/remote_runtime_live_test.dart
  )
fi

log "gateway, sessions, runbooks, memory MCP, and Launchpad smoke passed"
