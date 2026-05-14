#!/usr/bin/env bash
# Starts the Cloudflare pilot container with profile-specific harnesses and
# gateway-supervised memory services.
set -euo pipefail

# wait_for_tcp blocks until a colocated service accepts TCP connections.
wait_for_tcp() {
  host="$1"
  port="$2"
  deadline_seconds="$3"
  end_at=$((SECONDS + deadline_seconds))
  while ((SECONDS < end_at)); do
    if timeout 1 bash -c ":</dev/tcp/${host}/${port}" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for ${host}:${port}" >&2
  return 1
}

# require_safe_model_value rejects shell/YAML metacharacters in model settings.
require_safe_model_value() {
  name="$1"
  value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "${name} contains unsupported characters" >&2
    return 1
  fi
}

# require_safe_provider_url rejects characters that would break generated YAML.
require_safe_provider_url() {
  name="$1"
  value="$2"
  pattern='^https?://[A-Za-z0-9._:/%?&=+-]+$'
  if [[ ! "$value" =~ $pattern ]]; then
    echo "${name} contains an unsupported provider URL" >&2
    return 1
  fi
}

# write_model_config renders the cloud model config from Worker vars.
write_model_config() {
  provider_id="${AGENTAWESOME_MODEL_PROVIDER_ID:-openai}"
  model_id="${AGENTAWESOME_MODEL_ID:-gpt-5.4-mini}"
  wire_model="${AGENTAWESOME_OPENAI_MODEL:-$model_id}"
  provider_url="${AGENTAWESOME_OPENAI_CHAT_COMPLETIONS_URL:-https://api.openai.com/v1/chat/completions}"
  if [[ "$provider_id" != "openai" ]]; then
    echo "Unsupported cloud model provider: ${provider_id}" >&2
    return 1
  fi
  require_safe_model_value "AGENTAWESOME_MODEL_ID" "$model_id"
  require_safe_model_value "AGENTAWESOME_OPENAI_MODEL" "$wire_model"
  require_safe_provider_url "AGENTAWESOME_OPENAI_CHAT_COMPLETIONS_URL" "$provider_url"
  cat > /app/runtime/model.yaml <<EOF
# Generated at container startup from Cloudflare Worker model vars.
default: openai:${model_id}
providers:
  openai:
    adapter: openai
    auth: required
    api-key: OPENAI_API_KEY
    default: ${model_id}
    url: ${provider_url}
    models:
      - id: ${model_id}
        model: ${wire_model}
EOF
  echo "Cloudflare model config provider=openai model_id=${model_id} model=${wire_model} url=${provider_url}" >&2
}

mkdir -p /app/data /app/data/sessions /app/logs /app/runtime
export LOG_FORMAT="${LOG_FORMAT:-json}"
write_model_config
# Reset ephemeral log files so Cloudflare captures only this container lifecycle.
for log_file in /app/logs/gateway.log /app/logs/harness-doug.log /app/logs/harness-family.log /app/logs/memory-doug.log /app/logs/memory-family.log; do
  : > "${log_file}"
done
tail -n 0 -q -F /app/logs/gateway.log /app/logs/harness-doug.log /app/logs/harness-family.log /app/logs/memory-doug.log /app/logs/memory-family.log &

MEMORY_DOMAINS_JSON=${AGENTAWESOME_MEMORY_DOMAINS_JSON:-'[{"id":"doug","label":"Doug Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"},{"id":"family","label":"Family Memory","endpoint":"http://127.0.0.1:8091/mcp","health_url":"http://127.0.0.1:8091/healthz"}]'}
MEMORY_POLICY_JSON=${AGENTAWESOME_MEMORY_POLICY_JSON:-'{"actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","internal","private"]}'}
AGENT_PROFILES_JSON=${AGENTAWESOME_AGENT_PROFILES_JSON:-'[{"id":"doug","label":"Doug","app_name":"agent_awesome","user_id":"doug","harness_base_url":"http://127.0.0.1:8080/api","context_base_url":"http://127.0.0.1:8081/api/context","actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","internal","private"]},{"id":"family","label":"Family","app_name":"agent_awesome","user_id":"family","harness_base_url":"http://127.0.0.1:8082/api","context_base_url":"http://127.0.0.1:8083/api/context","actor":"agent:family","read_domains":["family"],"write_domains":["family"],"default_write_domain":"family","allowed_sensitivities":["public","internal","private"]}]'}
MEMORY_SERVICES_JSON=${AGENTAWESOME_MEMORY_SERVICES_JSON:-'[{"domain_id":"doug","name":"memory-doug","health_url":"http://127.0.0.1:8090/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8090","--db","/app/data/memory/doug/memory.db","--data","/app/data/memory/doug/files","--log-file","/app/logs/memory-doug.log","--snapshot-url","https://agent-awesome.com/internal/context-snapshot/doug"],"auto_start":true},{"domain_id":"family","name":"memory-family","health_url":"http://127.0.0.1:8091/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8091","--db","/app/data/memory/family/memory.db","--data","/app/data/memory/family/files","--log-file","/app/logs/memory-family.log","--snapshot-url","https://agent-awesome.com/internal/context-snapshot/family"],"auto_start":true}]'}
DOUG_TOOL_CONFIG=/app/config/tool.doug.yaml
FAMILY_TOOL_CONFIG=/app/config/tool.family.yaml
SLACK_MEMORY_TOOLS=${AGENTAWESOME_SLACK_MEMORY_TOOLS:-${SLACK_ENABLED:-false}}
if [[ "${SLACK_MEMORY_TOOLS,,}" == "true" ]]; then
  DOUG_TOOL_CONFIG=/app/config/tool.slack.doug.yaml
  FAMILY_TOOL_CONFIG=/app/config/tool.slack.family.yaml
  echo "Slack memory tool profile enabled for cloud harnesses" >&2
fi

agent-awesome \
  run \
  --model /app/runtime/model.yaml \
  --agent /app/config/agent.yaml \
  --tool "$DOUG_TOOL_CONFIG" \
  --context-api-addr 127.0.0.1:8081 \
  --session-db /app/data/sessions/doug.db \
  --log-file /app/logs/harness-doug.log \
  -- \
  web \
  --port 8080 \
  api \
  --webui_address 127.0.0.1:8080 &

agent-awesome \
  run \
  --model /app/runtime/model.yaml \
  --agent /app/config/agent.yaml \
  --tool "$FAMILY_TOOL_CONFIG" \
  --context-api-addr 127.0.0.1:8083 \
  --session-db /app/data/sessions/family.db \
  --log-file /app/logs/harness-family.log \
  -- \
  web \
  --port 8082 \
  api \
  --webui_address 127.0.0.1:8082 &

wait_for_tcp 127.0.0.1 8080 "${AGENTAWESOME_HARNESS_START_TIMEOUT_SECONDS:-30}"
wait_for_tcp 127.0.0.1 8082 "${AGENTAWESOME_HARNESS_START_TIMEOUT_SECONDS:-30}"

exec agent-gateway \
  --addr "${AGENTAWESOME_GATEWAY_ADDR:-0.0.0.0:8070}" \
  --harness-base-url "${AGENTAWESOME_HARNESS_API_BASE_URL:-http://127.0.0.1:8080/api}" \
  --context-base-url "${AGENTAWESOME_CONTEXT_API_BASE_URL:-http://127.0.0.1:8081/api/context}" \
  --memory-mcp-url "${AGENTAWESOME_MEMORY_MCP_URL:-http://127.0.0.1:8090/mcp}" \
  --memory-domains-json "$MEMORY_DOMAINS_JSON" \
  --memory-policy-json "$MEMORY_POLICY_JSON" \
  --agent-profiles-json "$AGENT_PROFILES_JSON" \
  --memory-services-json "$MEMORY_SERVICES_JSON" \
  --app-name "${AGENTAWESOME_APP_NAME:-agent_awesome}" \
  --user-id "${AGENTAWESOME_USER_ID:-doug}" \
  --model-provider-id "${AGENTAWESOME_MODEL_PROVIDER_ID:-openai}" \
  --model-id "${AGENTAWESOME_MODEL_ID:-gpt-5.4-mini}" \
  --log-file "${AGENTAWESOME_GATEWAY_LOG_FILE:-/app/logs/gateway.log}" \
  --auth-token "${AGENTAWESOME_GATEWAY_TOKEN:-}" \
  --request-timeout "${AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT:-10m}" \
  --service-start-timeout "${AGENTAWESOME_SERVICE_START_TIMEOUT:-45s}" \
  --slack-enabled="${SLACK_ENABLED:-false}" \
  --slack-socket-mode="${SLACK_SOCKET_MODE:-false}" \
  --slack-signing-secret "${SLACK_SIGNING_SECRET:-}" \
  --slack-bot-token "${SLACK_BOT_TOKEN:-}" \
  --slack-app-token "${SLACK_APP_TOKEN:-}" \
  --slack-allowed-team-id "${SLACK_ALLOWED_TEAM_ID:-}" \
  --slack-allowed-user-id "${SLACK_ALLOWED_USER_ID:-}" \
  --slack-allowed-channel-id "${SLACK_ALLOWED_CHANNEL_ID:-}"
