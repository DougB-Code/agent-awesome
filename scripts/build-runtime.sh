#!/usr/bin/env bash
# Builds Agent Awesome runtime service binaries used by the desktop app.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCECONTROL_ROOT="${SOURCECONTROL_ROOT:-"$ROOT_DIR/../tools/agent-awesome.com/sourcecontrol"}"
BUILD_SOURCECONTROL=1

# Prints usage for the runtime build helper.
usage() {
  cat <<'USAGE'
Usage:
  scripts/build-runtime.sh [build] [options]
  scripts/build-runtime.sh clean [options]
  scripts/build-runtime.sh paths [options]

Commands:
  build     Build service binaries used by the shipped runtime topology.
  clean     Remove service binaries created by this script.
  paths     Print the expected service binary paths.

Options:
  --no-sourcecontrol        Skip the sibling sourcecontrol daemon.
  --sourcecontrol-root DIR  Override the sibling sourcecontrol checkout path.
  -h, --help                Show this help text.

Environment:
  SOURCECONTROL_ROOT        Sibling sourcecontrol checkout path.
USAGE
}

# Prints a build-script status line.
log() {
  printf '[build] %s\n' "$*"
}

# Fails when a required command is missing.
require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$name" >&2
    exit 127
  fi
}

# Builds one Go command package into the path consumed by runtime topology.
build_go_binary() {
  local module_dir="$1"
  local package_path="$2"
  local output_path="$3"
  mkdir -p "$(dirname "$output_path")"
  log "building $output_path"
  (
    cd "$module_dir"
    go build -trimpath -buildvcs=false -o "$output_path" "$package_path"
  )
}

# Prints the service binary paths used by the shipped runtime topology.
print_paths() {
  printf '%s\n' \
    "$ROOT_DIR/harness/build/bin/agent-awesome" \
    "$ROOT_DIR/harness/build/bin/runbook-service" \
    "$ROOT_DIR/gateway/build/agent-gateway" \
    "$ROOT_DIR/memory/build/bin/memoryd"
  if [ "$BUILD_SOURCECONTROL" -eq 1 ]; then
    printf '%s\n' "$SOURCECONTROL_ROOT/build/bin/sourcecontrold"
  fi
}

# Builds every local service binary the desktop app can auto-start.
build_services() {
  require_command go
  build_go_binary "$ROOT_DIR/harness" ./cmd/agent-awesome \
    "$ROOT_DIR/harness/build/bin/agent-awesome"
  build_go_binary "$ROOT_DIR/harness" ./cmd/runbook-service \
    "$ROOT_DIR/harness/build/bin/runbook-service"
  build_go_binary "$ROOT_DIR/gateway" ./cmd/agent-gateway \
    "$ROOT_DIR/gateway/build/agent-gateway"
  build_go_binary "$ROOT_DIR/memory" ./cmd/memoryd \
    "$ROOT_DIR/memory/build/bin/memoryd"

  if [ "$BUILD_SOURCECONTROL" -eq 0 ]; then
    return
  fi
  if [ ! -f "$SOURCECONTROL_ROOT/go.mod" ]; then
    log "skipping sourcecontrol; not found at $SOURCECONTROL_ROOT"
    return
  fi
  build_go_binary "$SOURCECONTROL_ROOT" ./cmd/sourcecontrold \
    "$SOURCECONTROL_ROOT/build/bin/sourcecontrold"
}

# Removes binaries that were created for the runtime.
clean_services() {
  while IFS= read -r path; do
    if [ -n "$path" ]; then
      rm -f "$path"
      log "removed $path"
    fi
  done < <(print_paths)
}

# Parses build-script options.
parse_options() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-sourcecontrol)
        BUILD_SOURCECONTROL=0
        shift
        ;;
      --sourcecontrol-root)
        if [ "$#" -lt 2 ]; then
          printf '%s requires a directory argument\n' "$1" >&2
          exit 64
        fi
        SOURCECONTROL_ROOT="$2"
        shift 2
        ;;
      --sourcecontrol-root=*)
        SOURCECONTROL_ROOT="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done
  REMAINING_ARGS=("$@")
}

COMMAND="${1:-build}"
if [ "$#" -gt 0 ]; then
  shift
fi
parse_options "$@"
set -- "${REMAINING_ARGS[@]}"

case "$COMMAND" in
  build)
    build_services
    ;;
  clean)
    clean_services
    ;;
  paths)
    print_paths
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$COMMAND" >&2
    usage >&2
    exit 64
    ;;
esac
