#!/usr/bin/env sh
# Starts the Cloudflare pilot container with profile-specific harnesses and
# gateway-supervised memory services.
set -eu

mkdir -p /app/data /app/data/sessions /app/logs
touch /app/logs/harness-doug.log /app/logs/harness-family.log /app/logs/memory-doug.log /app/logs/memory-family.log
tail -n +1 -F /app/logs/harness-doug.log /app/logs/harness-family.log /app/logs/memory-doug.log /app/logs/memory-family.log &

MEMORY_DOMAINS_JSON=${AGENTAWESOME_MEMORY_DOMAINS_JSON:-'[{"id":"doug","label":"Doug Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"},{"id":"family","label":"Family Memory","endpoint":"http://127.0.0.1:8091/mcp","health_url":"http://127.0.0.1:8091/healthz"}]'}
MEMORY_POLICY_JSON=${AGENTAWESOME_MEMORY_POLICY_JSON:-'{"actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","internal","private"]}'}
AGENT_PROFILES_JSON=${AGENTAWESOME_AGENT_PROFILES_JSON:-'[{"id":"doug","label":"Doug","app_name":"agent_awesome","user_id":"doug","harness_base_url":"http://127.0.0.1:8080/api","context_base_url":"http://127.0.0.1:8081/api/context","actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","internal","private"]},{"id":"family","label":"Family","app_name":"agent_awesome","user_id":"family","harness_base_url":"http://127.0.0.1:8082/api","context_base_url":"http://127.0.0.1:8083/api/context","actor":"agent:family","read_domains":["family"],"write_domains":["family"],"default_write_domain":"family","allowed_sensitivities":["public","internal","private"]}]'}
MEMORY_SERVICES_JSON=${AGENTAWESOME_MEMORY_SERVICES_JSON:-'[{"domain_id":"doug","name":"memory-doug","health_url":"http://127.0.0.1:8090/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8090","--db","/app/data/memory/doug/memory.db","--data","/app/data/memory/doug/files","--log-file","/app/logs/memory-doug.log","--snapshot-url","https://agent-awesome.com/internal/context-snapshot/doug"],"auto_start":true},{"domain_id":"family","name":"memory-family","health_url":"http://127.0.0.1:8091/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8091","--db","/app/data/memory/family/memory.db","--data","/app/data/memory/family/files","--log-file","/app/logs/memory-family.log","--snapshot-url","https://agent-awesome.com/internal/context-snapshot/family"],"auto_start":true}]'}

agent-awesome \
  run \
  --model /app/config/model.yaml \
  --agent /app/config/agent.yaml \
  --tool /app/config/tool.doug.yaml \
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
  --model /app/config/model.yaml \
  --agent /app/config/agent.yaml \
  --tool /app/config/tool.family.yaml \
  --context-api-addr 127.0.0.1:8083 \
  --session-db /app/data/sessions/family.db \
  --log-file /app/logs/harness-family.log \
  -- \
  web \
  --port 8082 \
  api \
  --webui_address 127.0.0.1:8082 &

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
  --auth-token "${AGENTAWESOME_GATEWAY_TOKEN:-}" \
  --request-timeout "${AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT:-10m}" \
  --service-start-timeout "${AGENTAWESOME_SERVICE_START_TIMEOUT:-45s}" \
  --slack-enabled="${SLACK_ENABLED:-true}" \
  --slack-socket-mode="${SLACK_SOCKET_MODE:-false}" \
  --slack-signing-secret "${SLACK_SIGNING_SECRET:-}" \
  --slack-bot-token "${SLACK_BOT_TOKEN:-}" \
  --slack-app-token "${SLACK_APP_TOKEN:-}" \
  --slack-allowed-team-id "${SLACK_ALLOWED_TEAM_ID:-}" \
  --slack-allowed-user-id "${SLACK_ALLOWED_USER_ID:-}" \
  --slack-allowed-channel-id "${SLACK_ALLOWED_CHANNEL_ID:-}"
