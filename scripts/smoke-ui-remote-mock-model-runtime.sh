#!/usr/bin/env bash
# Runs the remote UI smoke with a deterministic OpenAI-compatible model server.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCK_MODEL_PORT="${AA_MOCK_MODEL_PORT:-18180}"
MOCK_MODEL_LOG="$ROOT_DIR/build/remote-runtime/mock-model.log"

# Stops the mock model process when the smoke exits.
cleanup() {
  if [ -n "${MOCK_MODEL_PID:-}" ]; then
    kill "$MOCK_MODEL_PID" >/dev/null 2>&1 || true
    wait "$MOCK_MODEL_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

mkdir -p "$(dirname "$MOCK_MODEL_LOG")"
python3 "$ROOT_DIR/scripts/mock-openai-chat.py" >"$MOCK_MODEL_LOG" 2>&1 &
MOCK_MODEL_PID="$!"

for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:$MOCK_MODEL_PORT/health" >/dev/null; then
    break
  fi
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$MOCK_MODEL_PORT/health" >/dev/null

export RUN_UI_REMOTE_SMOKE=1
export RUN_UI_REMOTE_MODEL_CHAT=1
export AA_DOCKER_HOST_NETWORK=1
export AA_LOCAL_MODEL_CHAT_URL="http://127.0.0.1:$MOCK_MODEL_PORT/v1/chat/completions"
export HOST_PORT="${HOST_PORT:-18079}"
export AA_HARNESS_PORT="${AA_HARNESS_PORT:-18081}"
export AA_CONTEXT_PORT="${AA_CONTEXT_PORT:-18082}"
export AA_RUNBOOK_PORT="${AA_RUNBOOK_PORT:-18083}"
export AA_MEMORY_PORT="${AA_MEMORY_PORT:-18084}"
export IMAGE_TAG="${IMAGE_TAG:-agent-awesome/remote-runtime:mock-model-smoke}"
export CONTAINER_NAME="${CONTAINER_NAME:-agent-awesome-mock-model-smoke-$$}"

exec "$ROOT_DIR/scripts/smoke-remote-runtime.sh"
