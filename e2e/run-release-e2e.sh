#!/usr/bin/env bash
# Builds release artifacts and verifies the desktop UI against the release container.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_id="${AGENTAWESOME_E2E_RUN_ID:-$(date +%Y%m%d%H%M%S)-$$}"
artifact_dir="${repo_root}/build/e2e/${run_id}"
network_name="agentawesome-e2e-${run_id}"
mock_image="agent-awesome-mock-llm:e2e-${run_id}"
gateway_image="agent-awesome-cloudflare:e2e-${run_id}"
mock_name="agentawesome-mock-llm-${run_id}"
gateway_name="agentawesome-cloudflare-${run_id}"
gateway_token="agentawesome-e2e-token-${run_id}"
ui_config_home="${artifact_dir}/ui-config"
mock_admin_url=""
gateway_root_url=""
auth_header=""
export DOCKER_CONFIG="${DOCKER_CONFIG:-${repo_root}/build/docker-config}"
export BUILDX_CONFIG="${BUILDX_CONFIG:-${repo_root}/build/docker-buildx}"

# cleanup collects container logs and removes Docker resources created by the run.
cleanup() {
  set +e
  mkdir -p "${artifact_dir}"
  if docker ps -a --format '{{.Names}}' | grep -qx "${gateway_name}"; then
    docker logs "${gateway_name}" > "${artifact_dir}/cloudflare-container.log" 2>&1
  fi
  if docker ps -a --format '{{.Names}}' | grep -qx "${mock_name}"; then
    docker logs "${mock_name}" > "${artifact_dir}/mock-llm.log" 2>&1
  fi
  if [[ -n "${mock_admin_url:-}" ]] && command -v curl >/dev/null 2>&1; then
    curl -fsS "${mock_admin_url}/requests" > "${artifact_dir}/mock-requests-on-exit.json" 2>/dev/null
  fi
  if [[ -n "${gateway_root_url:-}" && -n "${auth_header:-}" ]] && command -v curl >/dev/null 2>&1; then
    curl -fsS -H "${auth_header}" "${gateway_root_url}/api/gateway/status" > "${artifact_dir}/gateway-status-on-exit.json" 2>/dev/null
  fi
  docker rm -f "${gateway_name}" "${mock_name}" >/dev/null 2>&1
  docker network rm "${network_name}" >/dev/null 2>&1
}
trap cleanup EXIT

# require_command fails early when a required local tool is unavailable.
require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

# require_ui_display ensures the desktop UI can launch before expensive builds.
require_ui_display() {
  if [[ -n "${DISPLAY:-}" ]] || command -v xvfb-run >/dev/null 2>&1; then
    return 0
  fi
  echo "DISPLAY is not set and xvfb-run is unavailable; install Xvfb or run from a desktop session." >&2
  exit 1
}

# wait_for_http polls an HTTP endpoint until it responds successfully.
wait_for_http() {
  local url="$1"
  local header="${2:-}"
  local attempts="${3:-60}"
  local curl_args=(-fsS)
  if [[ -n "${header}" ]]; then
    curl_args+=(-H "${header}")
  fi
  for _ in $(seq 1 "${attempts}"); do
    if curl "${curl_args[@]}" "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for ${url}" >&2
  return 1
}

# wait_for_gateway_ready polls the release gateway until all dependencies are ready.
wait_for_gateway_ready() {
  local url="$1"
  local auth_header="$2"
  for _ in $(seq 1 90); do
    if curl -fsS -H "${auth_header}" "${url}" 2>/dev/null | grep -q '"ready":true'; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for gateway readiness at ${url}" >&2
  return 1
}

# published_port returns the host port Docker assigned to a container port.
published_port() {
  docker port "$1" "$2/tcp" | awk -F: 'NR == 1 {print $NF}'
}

# run_flutter_drive launches the UI integration test under Xvfb when needed.
run_flutter_drive() {
  local mock_admin_url="$1"
  local gateway_api_url="$2"
  local gateway_health_url="$3"
  local gateway_status_url="$4"
  local profile_path="${repo_root}/ui/runtime_profiles/cloudflare_context.json"
  local drive_command=(
    flutter drive
    -d linux
    --profile
    --driver=integration_test/driver.dart
    --target=integration_test/release_gateway_e2e_test.dart
    "--dart-define=AGENT_GATEWAY_BASE_URL=${gateway_api_url}"
    "--dart-define=AGENT_GATEWAY_HEALTH_URL=${gateway_health_url}"
    "--dart-define=AGENT_GATEWAY_STATUS_URL=${gateway_status_url}"
    "--dart-define=AGENTAWESOME_GATEWAY_TOKEN=${gateway_token}"
    "--dart-define=AGENTAWESOME_RUNTIME_PROFILE=${profile_path}"
    "--dart-define=AGENTAWESOME_WORKSPACE_ROOT=${repo_root}"
    "--dart-define=AUTO_START_LOCAL_SERVICES=false"
  )
  local env_args=(
    "AGENTAWESOME_CONFIG_HOME=${ui_config_home}"
    "AGENTAWESOME_E2E_MOCK_ADMIN_URL=${mock_admin_url}"
  )

  if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null 2>&1; then
    (cd "${repo_root}/ui" && env "${env_args[@]}" xvfb-run -a "${drive_command[@]}")
    return
  fi
  (cd "${repo_root}/ui" && env "${env_args[@]}" "${drive_command[@]}")
}

# run_gateway_api_smoke verifies the release gateway can proxy a real ADK run.
run_gateway_api_smoke() {
  local gateway_api_url="$1"
  local auth_header="$2"
  local prompt="release e2e api smoke prompt"
  local profile_header="X-Agent-Awesome-Profile: doug"
  local session_response
  local session_id
  local run_body
  local run_response

  session_response="$(
    curl -fsS \
      -H "${auth_header}" \
      -H "${profile_header}" \
      -H "Content-Type: application/json" \
      -X POST \
      -d '{"state":{}}' \
      "${gateway_api_url}/apps/agent_awesome/users/doug/sessions"
  )"
  printf '%s\n' "${session_response}" > "${artifact_dir}/api-smoke-session.json"
  session_id="$(
    python3 -c 'import json, sys; print(json.load(sys.stdin).get("id", ""))' \
      <<<"${session_response}"
  )"
  if [[ -z "${session_id}" ]]; then
    echo "Gateway API smoke did not receive a session id: ${session_response}" >&2
    return 1
  fi

  run_body="$(
    python3 - "${session_id}" "${prompt}" <<'PY'
import json
import sys

print(json.dumps({
    "appName": "agent_awesome",
    "userId": "doug",
    "sessionId": sys.argv[1],
    "streaming": False,
    "newMessage": {
        "role": "user",
        "parts": [{"text": sys.argv[2]}],
    },
}))
PY
  )"
  run_response="$(
    curl -fsS -N \
      -H "${auth_header}" \
      -H "${profile_header}" \
      -H "Content-Type: application/json" \
      -X POST \
      -d "${run_body}" \
      "${gateway_api_url}/run_sse"
  )"
  printf '%s\n' "${run_response}" > "${artifact_dir}/api-smoke.sse"
  if ! grep -q "mock llm e2e response: ${prompt}" "${artifact_dir}/api-smoke.sse"; then
    echo "Gateway API smoke did not receive the expected mock LLM response." >&2
    return 1
  fi
}

require_command curl
require_command docker
require_command flutter
require_command python3
require_ui_display

mkdir -p "${artifact_dir}" "${ui_config_home}" "${DOCKER_CONFIG}" "${BUILDX_CONFIG}"

docker network create "${network_name}" >/dev/null
docker build --file "${repo_root}/e2e/mockllm/Dockerfile" --tag "${mock_image}" "${repo_root}/e2e/mockllm"
docker build --file "${repo_root}/Dockerfile.cloudflare" --tag "${gateway_image}" "${repo_root}"

docker run --rm -d \
  --name "${mock_name}" \
  --network "${network_name}" \
  --network-alias mock-llm \
  -p 127.0.0.1::8080 \
  "${mock_image}" >/dev/null

mock_port="$(published_port "${mock_name}" 8080)"
mock_admin_url="http://127.0.0.1:${mock_port}"
wait_for_http "${mock_admin_url}/healthz"

memory_services_json="$(cat <<'JSON'
[{"domain_id":"doug","name":"memory-doug","health_url":"http://127.0.0.1:8090/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8090","--db","/app/data/memory/doug/memory.db","--data","/app/data/memory/doug/files","--log-file","/app/logs/memory-doug.log"],"auto_start":true},{"domain_id":"family","name":"memory-family","health_url":"http://127.0.0.1:8091/healthz","command":"/usr/local/bin/memoryd","arguments":["--addr","127.0.0.1:8091","--db","/app/data/memory/family/memory.db","--data","/app/data/memory/family/files","--log-file","/app/logs/memory-family.log"],"auto_start":true}]
JSON
)"

docker run --rm -d \
  --name "${gateway_name}" \
  --network "${network_name}" \
  -p 127.0.0.1::8070 \
  -e "AGENTAWESOME_GATEWAY_TOKEN=${gateway_token}" \
  -e "AGENTAWESOME_MODEL_ID=e2e-model" \
  -e "AGENTAWESOME_OPENAI_MODEL=e2e-wire-model" \
  -e "AGENTAWESOME_OPENAI_CHAT_COMPLETIONS_URL=http://mock-llm:8080/v1/chat/completions" \
  -e "AGENTAWESOME_MEMORY_SERVICES_JSON=${memory_services_json}" \
  -e "OPENAI_API_KEY=e2e-test-key" \
  -e "HTTP_PROXY=http://127.0.0.1:9" \
  -e "HTTPS_PROXY=http://127.0.0.1:9" \
  -e "NO_PROXY=mock-llm,127.0.0.1,localhost" \
  -e "SLACK_ENABLED=false" \
  "${gateway_image}" >/dev/null

gateway_port="$(published_port "${gateway_name}" 8070)"
gateway_root_url="http://127.0.0.1:${gateway_port}"
gateway_api_url="${gateway_root_url}/api"
auth_header="Authorization: Bearer ${gateway_token}"
wait_for_http "${gateway_root_url}/healthz"
wait_for_gateway_ready "${gateway_root_url}/api/gateway/status" "${auth_header}"
curl -fsS -H "${auth_header}" "${gateway_root_url}/api/gateway/status" > "${artifact_dir}/gateway-status.json"
run_gateway_api_smoke "${gateway_api_url}" "${auth_header}"
curl -fsS "${mock_admin_url}/reset" >/dev/null

(
  cd "${repo_root}/ui"
  flutter pub get
  flutter build linux --release \
    "--dart-define=AGENT_GATEWAY_BASE_URL=${gateway_api_url}" \
    "--dart-define=AGENT_GATEWAY_HEALTH_URL=${gateway_root_url}/healthz" \
    "--dart-define=AGENT_GATEWAY_STATUS_URL=${gateway_root_url}/api/gateway/beta-status" \
    "--dart-define=AGENTAWESOME_GATEWAY_TOKEN=${gateway_token}" \
    "--dart-define=AGENTAWESOME_RUNTIME_PROFILE=${repo_root}/ui/runtime_profiles/cloudflare_context.json" \
    "--dart-define=AGENTAWESOME_WORKSPACE_ROOT=${repo_root}" \
    "--dart-define=AUTO_START_LOCAL_SERVICES=false"
)

run_flutter_drive \
  "${mock_admin_url}" \
  "${gateway_api_url}" \
  "${gateway_root_url}/healthz" \
  "${gateway_root_url}/api/gateway/beta-status" \
  2>&1 | tee "${artifact_dir}/flutter-drive.log"

curl -fsS "${mock_admin_url}/requests" > "${artifact_dir}/mock-requests.json"
echo "Release E2E completed. Artifacts: ${artifact_dir}"
