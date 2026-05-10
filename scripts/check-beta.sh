#!/usr/bin/env bash
# This script runs the local release gate for a small Agent Awesome beta.
set -euo pipefail

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

# run_go_tests executes one module's complete Go test suite.
run_go_tests() {
  local module="$1"
  (cd "$module" && go test ./...)
}

# run_flutter_checks verifies the desktop UI when it is included in the checkout.
run_flutter_checks() {
  local ui_dir="$1"
  if [[ ! -f "$ui_dir/pubspec.yaml" ]]; then
    return
  fi
  (cd "$ui_dir" && flutter analyze && flutter test)
}

# run_provision_dry_run proves the beta deploy path renders isolated cloud assets.
run_provision_dry_run() {
  local root="$1"
  local output_dir="$root/build/provision/beta-smoke"
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

# main coordinates every beta-readiness check.
main() {
  local root
  root="$(repo_root)"
  cd "$root"

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

  npm run docs:build
  npm --prefix deploy/cloudflare/worker run check
  npm --prefix deploy/cloudflare/worker run test

  run_go_tests gateway
  run_go_tests harness
  run_go_tests memory
  run_go_tests provision
  run_provision_dry_run "$root"
  run_flutter_checks ui
}

main "$@"
