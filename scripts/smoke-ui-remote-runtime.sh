#!/usr/bin/env bash
# Runs the Docker remote-runtime smoke plus the Flutter UI live path.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export RUN_UI_REMOTE_SMOKE=1
export HOST_PORT="${HOST_PORT:-18072}"
export IMAGE_TAG="${IMAGE_TAG:-agent-awesome/remote-runtime:ui-smoke}"
export CONTAINER_NAME="${CONTAINER_NAME:-agent-awesome-ui-smoke-$$}"

exec "$ROOT_DIR/scripts/smoke-remote-runtime.sh"
