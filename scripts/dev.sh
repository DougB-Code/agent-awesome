#!/usr/bin/env bash
# Runs common local Agent Awesome development commands.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI_DIR="$ROOT_DIR/ui"
BUILD_RUNTIME="$ROOT_DIR/scripts/build-runtime.sh"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-linux}"
BUILD_ARGS=()
FLUTTER_ARGS=()

# Prints usage for the local development helper.
usage() {
  cat <<'USAGE'
Usage:
  scripts/dev.sh build [runtime options]
  scripts/dev.sh run [runtime options] [-- flutter args]
  scripts/dev.sh ui [flutter args]
  scripts/dev.sh clean [runtime options]
  scripts/dev.sh paths [runtime options]
  scripts/dev.sh test [flutter test args]

Commands:
  build   Build local runtime service binaries.
  run     Build runtime service binaries, then run the Flutter UI.
  ui      Run the Flutter UI without rebuilding runtime services.
  clean   Remove runtime service binaries.
  paths   Print expected runtime service binary paths.
  test    Run Flutter tests from the UI project.

Runtime options are forwarded to scripts/build-runtime.sh. For example:
  scripts/dev.sh build --no-sourcecontrol
  scripts/dev.sh run --no-sourcecontrol -- --dart-define=FOO=bar

Environment:
  FLUTTER_BIN       Flutter executable. Defaults to flutter.
  FLUTTER_DEVICE    Flutter run device. Defaults to linux.
  SOURCECONTROL_ROOT Sibling sourcecontrol checkout path for runtime builds.
USAGE
}

# Fails when a required file is missing.
require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf 'Missing required file: %s\n' "$path" >&2
    exit 127
  fi
}

# Splits run arguments into runtime build args and Flutter args.
split_run_args() {
  BUILD_ARGS=()
  FLUTTER_ARGS=()
  local target=build
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      target=flutter
      shift
      continue
    fi
    if [ "$target" = build ]; then
      BUILD_ARGS+=("$1")
    else
      FLUTTER_ARGS+=("$1")
    fi
    shift
  done
}

# Builds runtime service binaries through the canonical runtime helper.
dev_build() {
  require_file "$BUILD_RUNTIME"
  "$BUILD_RUNTIME" build "$@"
}

# Removes runtime service binaries through the canonical runtime helper.
dev_clean() {
  require_file "$BUILD_RUNTIME"
  "$BUILD_RUNTIME" clean "$@"
}

# Prints runtime service binary paths through the canonical runtime helper.
dev_paths() {
  require_file "$BUILD_RUNTIME"
  "$BUILD_RUNTIME" paths "$@"
}

# Runs Flutter from the UI project.
dev_ui() {
  (
    cd "$UI_DIR"
    "$FLUTTER_BIN" pub get
    "$FLUTTER_BIN" run -d "$FLUTTER_DEVICE" "$@"
  )
}

# Builds runtime services and then launches the UI.
dev_run() {
  split_run_args "$@"
  dev_build "${BUILD_ARGS[@]}"
  dev_ui "${FLUTTER_ARGS[@]}"
}

# Runs Flutter tests from the UI project.
dev_test() {
  (
    cd "$UI_DIR"
    "$FLUTTER_BIN" test "$@"
  )
}

COMMAND="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$COMMAND" in
  build)
    dev_build "$@"
    ;;
  run)
    dev_run "$@"
    ;;
  ui)
    dev_ui "$@"
    ;;
  clean)
    dev_clean "$@"
    ;;
  paths)
    dev_paths "$@"
    ;;
  test)
    dev_test "$@"
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
