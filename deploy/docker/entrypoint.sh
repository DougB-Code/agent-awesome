#!/usr/bin/env bash
# Starts the remote Agent Awesome runtime inside one container.

set -euo pipefail

PIDS=()

# Prints a timestamped runtime log line.
log() {
  printf '[agent-awesome-container] %s\n' "$*"
}

# Returns the first non-empty value from a variable or fallback.
defaulted() {
  local value="$1"
  local fallback="$2"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

# Starts a long-running child process and remembers its pid.
start_service() {
  local name="$1"
  shift
  log "starting ${name}: $*"
  "$@" &
  PIDS+=("$!")
}

# Stops every child process when the container receives a shutdown signal.
shutdown() {
  log "stopping services"
  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
  wait || true
}

# Waits for an HTTP health endpoint before dependent services start.
wait_for_health() {
  local name="$1"
  local url="$2"
  for _ in $(seq 1 120); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "${name} is healthy"
      return 0
    fi
    sleep 0.5
  done
  log "${name} did not become healthy at ${url}"
  return 1
}

# Starts an optional llama.cpp-compatible model server when configured.
start_optional_model() {
  local model_path="${AA_LOCAL_MODEL_PATH:-}"
  if [ -z "$model_path" ]; then
    return 0
  fi
  local llama_server="${AA_LLAMA_SERVER:-llama-server}"
  if ! command -v "$llama_server" >/dev/null 2>&1; then
    log "AA_LOCAL_MODEL_PATH is set but ${llama_server} is not available"
    return 1
  fi
  local host="${AA_LOCAL_MODEL_HOST:-127.0.0.1}"
  local port="${AA_LOCAL_MODEL_PORT:-11667}"
  local context="${AA_LOCAL_MODEL_CONTEXT:-8192}"
  start_service "model" "$llama_server" \
    --host "$host" \
    --port "$port" \
    --ctx-size "$context" \
    --model "$model_path"
  wait_for_health "model" "http://${host}:${port}/health"
}

trap shutdown EXIT INT TERM

AA_CONFIG_DIR="$(defaulted "${AA_CONFIG_DIR:-}" "/opt/agent-awesome/config")"
AA_DATA_DIR="$(defaulted "${AA_DATA_DIR:-}" "/var/lib/agent-awesome")"
AA_LOG_DIR="$(defaulted "${AA_LOG_DIR:-}" "/var/log/agent-awesome")"
AA_GATEWAY_ADDR="$(defaulted "${AA_GATEWAY_ADDR:-}" "0.0.0.0:8070")"
AA_GATEWAY_PUBLIC_BASE_URL="$(defaulted "${AA_GATEWAY_PUBLIC_BASE_URL:-}" "http://127.0.0.1:8070/api")"
AA_HARNESS_ADDR="$(defaulted "${AA_HARNESS_ADDR:-}" "127.0.0.1:8080")"
AA_CONTEXT_ADDR="$(defaulted "${AA_CONTEXT_ADDR:-}" "127.0.0.1:8081")"
AA_RUNBOOK_ADDR="$(defaulted "${AA_RUNBOOK_ADDR:-}" "127.0.0.1:8092")"
AA_MEMORY_ADDR="$(defaulted "${AA_MEMORY_ADDR:-}" "127.0.0.1:8090")"
AA_APP_NAME="$(defaulted "${AA_APP_NAME:-}" "Agent Awesome")"
AA_USER_ID="$(defaulted "${AA_USER_ID:-}" "remote-user")"
AA_MODEL_PROVIDER_ID="$(defaulted "${AA_MODEL_PROVIDER_ID:-}" "local-gemma")"
AA_MODEL_ID="$(defaulted "${AA_MODEL_ID:-}" "gemma")"
AA_PROFILE_ID="$(defaulted "${AA_PROFILE_ID:-}" "agent-awesome")"
AA_LOCAL_MODEL_CHAT_URL="$(defaulted "${AA_LOCAL_MODEL_CHAT_URL:-}" "http://127.0.0.1:11667/v1/chat/completions")"
AA_LOCAL_MODEL_NAME="$(defaulted "${AA_LOCAL_MODEL_NAME:-}" "gemma")"
AA_GATEWAY_HEALTH_URL="http://127.0.0.1:${AA_GATEWAY_ADDR##*:}/healthz"
export AA_LOCAL_MODEL_CHAT_URL AA_LOCAL_MODEL_NAME

mkdir -p \
  "$AA_CONFIG_DIR/runbooks" \
  "$AA_CONFIG_DIR/command/parsers" \
  "$AA_DATA_DIR/memory/files" \
  "$AA_DATA_DIR/runbook" \
  "$AA_DATA_DIR/command" \
  "$AA_DATA_DIR/workdir" \
  "$AA_LOG_DIR"

start_optional_model

start_service "memory" memoryd \
  --addr "$AA_MEMORY_ADDR" \
  --db "$AA_DATA_DIR/memory/memory.db" \
  --data "$AA_DATA_DIR/memory/files" \
  --log-file "$AA_LOG_DIR/memory.log"
wait_for_health "memory" "http://${AA_MEMORY_ADDR}/healthz"

start_service "runbook" runbook-service \
  --addr "$AA_RUNBOOK_ADDR" \
  --definitions "$AA_CONFIG_DIR/runbooks" \
  --db "$AA_DATA_DIR/runbook/runbook.db" \
  --launchpad-db "$AA_DATA_DIR/runbook/launchpad.db" \
  --runtime-targets-db "$AA_DATA_DIR/runbook/runtime-targets.db" \
  --harness-context-base-url "http://${AA_CONTEXT_ADDR}/api/context" \
  --tool "$AA_CONFIG_DIR/tool.yaml" \
  --command-data-dir "$AA_DATA_DIR/command" \
  --command-parser-dir "$AA_CONFIG_DIR/command/parsers" \
  --command-allow-workdir "$AA_DATA_DIR/workdir" \
  --log-file "$AA_LOG_DIR/runbook.log"
wait_for_health "runbook" "http://${AA_RUNBOOK_ADDR}/healthz"

start_service "harness" agent-awesome run \
  --model "$AA_CONFIG_DIR/model.yaml" \
  --agent "$AA_CONFIG_DIR/agent.yaml" \
  --tool "$AA_CONFIG_DIR/tool.yaml" \
  --context-api-addr "$AA_CONTEXT_ADDR" \
  --session-db "$AA_DATA_DIR/session.db" \
  --command-data-dir "$AA_DATA_DIR/command" \
  --command-parser-dir "$AA_CONFIG_DIR/command/parsers" \
  --command-allow-workdir "$AA_DATA_DIR/workdir" \
  --log-file "$AA_LOG_DIR/harness.log" \
  --provider "$AA_MODEL_PROVIDER_ID" \
  --model-id "$AA_MODEL_ID" \
  -- web --port "${AA_HARNESS_ADDR##*:}" api --webui_address "$AA_HARNESS_ADDR"
wait_for_health "harness context" "http://${AA_CONTEXT_ADDR}/api/context/healthz"

MEMORY_DOMAINS_JSON="[{\"id\":\"memory\",\"label\":\"Memory\",\"endpoint\":\"http://${AA_MEMORY_ADDR}/mcp\",\"health_url\":\"http://${AA_MEMORY_ADDR}/healthz\"}]"
MEMORY_POLICY_JSON="{\"actor\":\"agent:${AA_PROFILE_ID}\",\"read_domains\":[\"memory\"],\"write_domains\":[\"memory\"],\"default_write_domain\":\"memory\",\"allowed_sensitivities\":[\"public\",\"internal\",\"private\"]}"
AGENT_PROFILES_JSON="[{\"id\":\"${AA_PROFILE_ID}\",\"label\":\"Agent Awesome\",\"app_name\":\"${AA_APP_NAME}\",\"user_id\":\"${AA_USER_ID}\",\"actor\":\"agent:${AA_PROFILE_ID}\",\"read_domains\":[\"memory\"],\"write_domains\":[\"memory\"],\"default_write_domain\":\"memory\",\"allowed_sensitivities\":[\"public\",\"internal\",\"private\"]}]"
MEMORY_SERVICES_JSON="[{\"domain_id\":\"memory\",\"name\":\"memory\",\"health_url\":\"http://${AA_MEMORY_ADDR}/healthz\",\"auto_start\":false}]"

start_service "gateway" agent-gateway \
  --addr "$AA_GATEWAY_ADDR" \
  --gateway-base-url "$AA_GATEWAY_PUBLIC_BASE_URL" \
  --harness-base-url "http://${AA_HARNESS_ADDR}/api" \
  --context-base-url "http://${AA_CONTEXT_ADDR}/api/context" \
  --runbook-base-url "http://${AA_RUNBOOK_ADDR}/api/runbooks" \
  --memory-mcp-url "http://${AA_MEMORY_ADDR}/mcp" \
  --memory-domains-json "$MEMORY_DOMAINS_JSON" \
  --memory-policy-json "$MEMORY_POLICY_JSON" \
  --agent-profiles-json "$AGENT_PROFILES_JSON" \
  --memory-services-json "$MEMORY_SERVICES_JSON" \
  --app-name "$AA_APP_NAME" \
  --user-id "$AA_USER_ID" \
  --auth-token "${AGENTAWESOME_GATEWAY_TOKEN:-}" \
  --model-provider-id "$AA_MODEL_PROVIDER_ID" \
  --model-id "$AA_MODEL_ID" \
  --log-file "$AA_LOG_DIR/gateway.log"
wait_for_health "gateway" "$AA_GATEWAY_HEALTH_URL"

log "remote runtime ready at ${AA_GATEWAY_PUBLIC_BASE_URL}"
wait -n "${PIDS[@]}"
