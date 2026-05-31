#!/usr/bin/env bash
# Runs the remote UI smoke with a real mounted Gemma model through llama.cpp.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${AA_LOCAL_GEMMA_MODEL:?Set AA_LOCAL_GEMMA_MODEL to your local Gemma GGUF path.}"

export RUN_UI_REMOTE_SMOKE=1
export RUN_UI_REMOTE_MODEL_CHAT=1
export HOST_PORT="${HOST_PORT:-18076}"
export IMAGE_TAG="${IMAGE_TAG:-agent-awesome/remote-runtime:model-smoke}"
export CONTAINER_NAME="${CONTAINER_NAME:-agent-awesome-model-smoke-$$}"

exec "$ROOT_DIR/scripts/smoke-remote-runtime.sh"
