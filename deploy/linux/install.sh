#!/usr/bin/env bash
# Installs an extracted Agent Awesome Linux release bundle for the current user.

set -euo pipefail

# Resolve the directory containing this script so the installer can be run from
# a file manager, terminal, or another working directory.
bundle_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_root="${AGENTAWESOME_INSTALL_ROOT:-${HOME}/.local/opt/agent-awesome}"
desktop_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
bin_dir="${HOME}/.local/bin"
desktop_file="${desktop_dir}/agent-awesome.desktop"

# validate_install_root rejects targets where replacement would be destructive.
validate_install_root() {
  if [[ -z "$install_root" || "$install_root" == "/" || "$install_root" == "$HOME" ]]; then
    printf 'Refusing unsafe AGENTAWESOME_INSTALL_ROOT: %s\n' "$install_root" >&2
    exit 1
  fi
}

# copy_bundle installs the whole release directory without requiring sudo.
copy_bundle() {
  if [[ "$bundle_root" == "$install_root" ]]; then
    return
  fi
  rm -rf "${install_root}.tmp"
  mkdir -p "$(dirname "$install_root")"
  cp -a "$bundle_root" "${install_root}.tmp"
  rm -rf "$install_root"
  mv "${install_root}.tmp" "$install_root"
}

# write_desktop_entry makes the app visible to desktop launchers.
write_desktop_entry() {
  mkdir -p "$desktop_dir" "$bin_dir"
  ln -sf "${install_root}/agentawesome_ui" "${bin_dir}/agent-awesome"
  cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Agent Awesome
Comment=Desktop assistant workspace
Exec=${install_root}/agentawesome_ui
Path=${install_root}
Terminal=false
Categories=Utility;Office;
EOF
}

# main applies executable bits that can be lost by archive tooling, then
# registers the app in user-local XDG locations.
main() {
  validate_install_root
  copy_bundle
  chmod 0755 "${install_root}/agentawesome_ui"
  chmod 0755 "${install_root}/install.sh"
  chmod 0755 "${install_root}/harness/build/profiles/agent-awesome/bin/"*
  write_desktop_entry
  printf 'Agent Awesome installed to %s\n' "$install_root"
  printf 'Desktop entry written to %s\n' "$desktop_file"
  printf 'Command symlink written to %s\n' "${bin_dir}/agent-awesome"
}

main "$@"
