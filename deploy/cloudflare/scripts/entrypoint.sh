#!/usr/bin/env sh
# Starts the Cloudflare pilot container by letting the gateway supervise the
# colocated harness and memory services.
set -eu

mkdir -p /app/data /app/logs
touch /app/logs/harness.log /app/logs/memory.log
tail -n +1 -F /app/logs/harness.log /app/logs/memory.log &

MEMORY_DOMAINS_JSON=${AGENTAWESOME_MEMORY_DOMAINS_JSON:-'[{"id":"memory","label":"Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"}]'}
MEMORY_POLICY_JSON=${AGENTAWESOME_MEMORY_POLICY_JSON:-'{"actor":"agent:agent-awesome","read_domains":["memory"],"write_domains":["memory"],"default_write_domain":"memory","allowed_sensitivities":["public","internal","private"]}'}
MEMORY_SERVICES_JSON=${AGENTAWESOME_MEMORY_SERVICES_JSON:-'[{"domain_id":"memory","name":"memory","health_url":"http://127.0.0.1:8090/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8090","--db","/app/data/memory/memory.db","--data","/app/data/memory/files","--log-file","/app/logs/memory.log"],"auto_start":true}]'}

exec agent-gateway \
  --addr "${AGENTAWESOME_GATEWAY_ADDR:-0.0.0.0:8070}" \
  --harness-base-url "${AGENTAWESOME_HARNESS_API_BASE_URL:-http://127.0.0.1:8080/api}" \
  --context-base-url "${AGENTAWESOME_CONTEXT_API_BASE_URL:-http://127.0.0.1:8081/api/context}" \
  --memory-mcp-url "${AGENTAWESOME_MEMORY_MCP_URL:-http://127.0.0.1:8090/mcp}" \
  --memory-domains-json "$MEMORY_DOMAINS_JSON" \
  --memory-policy-json "$MEMORY_POLICY_JSON" \
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
  --slack-allowed-channel-id "${SLACK_ALLOWED_CHANNEL_ID:-}" \
  --harness-auto-start \
  --harness-command /usr/local/bin/agent-awesome \
  --harness-workdir /app \
  --harness-arg run \
  --harness-arg --model \
  --harness-arg /app/config/model.yaml \
  --harness-arg --agent \
  --harness-arg /app/config/agent.yaml \
  --harness-arg --tool \
  --harness-arg /app/config/tool.yaml \
  --harness-arg --context-api-addr \
  --harness-arg 127.0.0.1:8081 \
  --harness-arg --log-file \
  --harness-arg /app/logs/harness.log \
  --harness-arg -- \
  --harness-arg web \
  --harness-arg --port \
  --harness-arg 8080 \
  --harness-arg api \
  --harness-arg --webui_address \
  --harness-arg 127.0.0.1:8080
