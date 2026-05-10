#!/usr/bin/env bash
# This script runs the local release gate for a small Agent Awesome beta.
set -euo pipefail

# print_section writes one clear beta-check phase header.
print_section() {
  printf '\n==> %s\n' "$1"
}

# repo_root returns the repository root regardless of the caller's directory.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# require_file fails early when a release-critical source or lockfile is absent.
require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'missing required beta file: %s\n' "$path" >&2
    exit 1
  fi
}

# require_node_22 verifies the Worker-compatible Node major version.
require_node_22() {
  local major
  major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ "$major" -lt 22 ]]; then
    printf 'Node.js 22 or newer is required; found %s\n' "$(node --version)" >&2
    printf 'Install the pinned version from .tool-versions before running beta checks.\n' >&2
    exit 1
  fi
}

# run_go_tests executes one module's complete Go test suite.
run_go_tests() {
  local module="$1"
  print_section "Go tests: $module"
  (cd "$module" && go test ./...)
}

# run_flutter_checks verifies the desktop UI when it is included in the checkout.
run_flutter_checks() {
  local ui_dir="$1"
  if [[ ! -f "$ui_dir/pubspec.yaml" ]]; then
    return
  fi
  print_section "Flutter checks"
  (cd "$ui_dir" && flutter analyze && flutter test)
}

# run_provision_dry_run proves the beta deploy path renders isolated cloud assets.
run_provision_dry_run() {
  local root="$1"
  local output_dir="$root/build/provision/beta-smoke"
  print_section "Provisioner dry run"
  mkdir -p "$output_dir"
  (
    cd "$root/provision"
    go run ./cmd/agent-awesome-provision cloudflare apply \
      --agent-id beta-smoke \
      --user-id beta-smoke \
      --hostname beta-smoke.example.com \
      --slack \
      --slack-allowed-team-id T_BETA_SMOKE \
      --slack-allowed-user-id U_BETA_SMOKE \
      --slack-allowed-channel-id C_BETA_SMOKE \
      --repo-root "$root" \
      --output-dir "$output_dir" \
      --state-dir "$root/build/provision/state" \
      --dry-run \
      --json > "$output_dir/dry-run.json"
  )
}

# run_config_preflights validates service config without starting servers.
run_config_preflights() {
  local root="$1"
  print_section "Config preflights"
  mkdir -p "$root/build/beta-preflight"
  (
    cd "$root/gateway"
    go run ./cmd/agent-gateway --check-config --addr 127.0.0.1:0
  )
  (
    cd "$root/memory"
    go run ./cmd/memoryd --check-config \
      --addr 127.0.0.1:0 \
      --db "$root/build/beta-preflight/memory.db" \
      --data "$root/build/beta-preflight/memory-data"
  )
  (
    cd "$root/provision"
    go run ./cmd/agent-awesome-provision check --repo-root "$root"
  )
}

# main coordinates every beta-readiness check.
main() {
  local root
  root="$(repo_root)"
  cd "$root"

  print_section "Toolchain"
  go version
  node --version
  npm --version
  require_node_22

  print_section "Required beta assets"
  require_file .tool-versions
  require_file package-lock.json
  require_file deploy/cloudflare/worker/package-lock.json
  require_file deploy/cloudflare/worker/src/index.ts
  require_file deploy/cloudflare/worker/scripts/smoke-test.mjs
  require_file Dockerfile.cloudflare
  require_file gateway/go.sum
  require_file harness/go.sum
  require_file memory/go.sum
  require_file provision/go.sum
  require_file ui/pubspec.lock

  print_section "Documentation build"
  npm run docs:build

  run_go_tests gateway
  run_go_tests harness
  run_go_tests memory
  run_go_tests provision
  run_config_preflights "$root"

  print_section "Cloudflare Worker checks"
  npm --prefix deploy/cloudflare/worker run test
  npm --prefix deploy/cloudflare/worker run check

  run_provision_dry_run "$root"
  run_flutter_checks ui

  print_section "Beta checks passed"
}

main "$@"
