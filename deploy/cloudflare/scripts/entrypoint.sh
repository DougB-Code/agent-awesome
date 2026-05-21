#!/usr/bin/env bash
# Starts the Cloudflare container gateway with harness-hosted control services.
set -euo pipefail

config_dir="${AGENTAWESOME_CONFIG_DIR:-/app/config}"
data_dir="${AGENTAWESOME_DATA_DIR:-/app/data}"
log_dir="${AGENTAWESOME_LOG_DIR:-/app/logs}"
app_name="${AGENTAWESOME_APP_NAME:-agent_awesome}"
user_id="${AGENTAWESOME_USER_ID:-doug}"
provider_id="${AGENTAWESOME_MODEL_PROVIDER_ID:-openai}"
model_id="${AGENTAWESOME_MODEL_ID:-gpt-5.4-mini}"
model_name="${AGENTAWESOME_OPENAI_MODEL:-${model_id}}"
chat_url="${AGENTAWESOME_OPENAI_CHAT_COMPLETIONS_URL:-https://api.openai.com/v1/chat/completions}"
harness_port="${AGENTAWESOME_HARNESS_PORT:-8080}"

mkdir -p \
  "${config_dir}/command/parsers" \
  "${config_dir}/workflows" \
  "${data_dir}/harness" \
  "${data_dir}/workflow" \
  "${data_dir}/command" \
  "${data_dir}/memory/doug/files" \
  "${data_dir}/memory/family/files" \
  "${log_dir}"

runtime_model="${config_dir}/model.runtime.yaml"
cat >"${runtime_model}" <<YAML
default: ${provider_id}:${model_id}
providers:
  ${provider_id}:
    adapter: openai
    auth: required
    api-key: OPENAI_API_KEY
    url: ${chat_url}
    default: ${model_id}
    models:
      - id: ${model_id}
        model: ${model_name}
YAML

if [[ -z "${AGENTAWESOME_MEMORY_DOMAINS_JSON:-}" ]]; then
  export AGENTAWESOME_MEMORY_DOMAINS_JSON='[{"id":"doug","label":"Doug Memory","endpoint":"http://127.0.0.1:8090/mcp","health_url":"http://127.0.0.1:8090/healthz"},{"id":"family","label":"Family Memory","endpoint":"http://127.0.0.1:8091/mcp","health_url":"http://127.0.0.1:8091/healthz"}]'
fi

if [[ -z "${AGENTAWESOME_MEMORY_SERVICES_JSON:-}" ]]; then
  export AGENTAWESOME_MEMORY_SERVICES_JSON='[{"domain_id":"doug","name":"memory-doug","health_url":"http://127.0.0.1:8090/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8090","--db","/app/data/memory/doug/memory.db","--data","/app/data/memory/doug/files","--log-file","/app/logs/memory-doug.log"],"auto_start":true},{"domain_id":"family","name":"memory-family","health_url":"http://127.0.0.1:8091/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8091","--db","/app/data/memory/family/memory.db","--data","/app/data/memory/family/files","--log-file","/app/logs/memory-family.log"],"auto_start":true}]'
fi

if [[ -z "${AGENTAWESOME_AGENT_PROFILES_JSON:-}" ]]; then
  export AGENTAWESOME_AGENT_PROFILES_JSON='[{"id":"doug","label":"Doug","app_name":"agent_awesome","user_id":"doug","actor":"agent:doug","read_domains":["doug"],"write_domains":["doug"],"default_write_domain":"doug","allowed_sensitivities":["public","internal","private"]},{"id":"family","label":"Family","app_name":"agent_awesome","user_id":"family","actor":"agent:family","read_domains":["family"],"write_domains":["family"],"default_write_domain":"family","allowed_sensitivities":["public","internal","private"]}]'
fi

export AGENTAWESOME_MODEL_PROVIDER_ID="${provider_id}"
export AGENTAWESOME_MODEL_ID="${model_id}"
export AGENTAWESOME_HARNESS_EMBEDDED_SERVICES="${AGENTAWESOME_HARNESS_EMBEDDED_SERVICES:-true}"

gateway_args=(
  --harness-embedded-services
  --harness-auto-start
  --harness-command /usr/local/bin/agent-awesome
  --harness-arg run
  --harness-arg --model
  --harness-arg "${runtime_model}"
  --harness-arg --agent
  --harness-arg "${AGENTAWESOME_AGENT_CONFIG:-${config_dir}/agent.yaml}"
  --harness-arg --tool
  --harness-arg "${AGENTAWESOME_TOOL_CONFIG:-${config_dir}/tool.yaml}"
  --harness-arg --provider
  --harness-arg "${provider_id}"
  --harness-arg --model-id
  --harness-arg "${model_id}"
  --harness-arg --session-db
  --harness-arg "${data_dir}/harness/sessions.db"
  --harness-arg --workflow-definitions
  --harness-arg "${config_dir}/workflows"
  --harness-arg --workflow-db
  --harness-arg "${data_dir}/workflow/workflow.db"
  --harness-arg --command-data-dir
  --harness-arg "${data_dir}/command"
  --harness-arg --command-parser-dir
  --harness-arg "${config_dir}/command/parsers"
  --harness-arg --command-allow-workdir
  --harness-arg /app
  --harness-arg --
  --harness-arg web
  --harness-arg --port
  --harness-arg "${harness_port}"
  --harness-arg api
  --harness-arg --webui_address
  --harness-arg "127.0.0.1:${harness_port}"
)

exec /usr/local/bin/agent-gateway "${gateway_args[@]}" "$@"
