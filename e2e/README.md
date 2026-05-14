# Release E2E Suite

This suite builds and runs the Cloudflare release container, points it at an
OpenAI-compatible mock provider, launches the Flutter desktop UI, and verifies
chat and task workflows travel through the rendered UI to the release gateway
and harness.

## Local Setup

The suite needs Docker, Flutter with Linux desktop support, and either a real
desktop display or `xvfb-run`. On Ubuntu or Debian development hosts, install
the same Linux desktop packages used by CI:

```sh
sudo apt-get update
sudo apt-get install -y clang cmake libgtk-3-dev liblzma-dev ninja-build pkg-config xvfb
```

Make sure Docker is running and the current user can run `docker` without an
interactive sudo prompt. If Flutter Linux desktop support is not already
enabled, enable it once:

```sh
flutter config --enable-linux-desktop
flutter doctor
```

Run the suite from the repository root:

```sh
./e2e/run-release-e2e.sh
```

When `DISPLAY` is set, the script launches the Flutter desktop UI on that
display. When `DISPLAY` is not set but `xvfb-run` is installed, it automatically
wraps `flutter drive` in `xvfb-run -a`. If both are missing, it exits before the
expensive Docker and Flutter builds with:

```text
DISPLAY is not set and xvfb-run is unavailable; install Xvfb or run from a desktop session.
```

The script writes diagnostic logs to `build/e2e`, runs the release container on
a dedicated Docker network, and points model traffic at the mock provider URL
instead of a hosted LLM provider. The gateway container also runs with HTTP/S
proxy variables set to a closed local port and `NO_PROXY` limited to the mock
provider and localhost services, so accidental external model calls fail during
the suite.

Coverage includes:

- release Docker image build and startup readiness
- mock-provider model URL, wire model, and bearer-token wiring
- direct gateway session and `run_sse` API smoke
- rendered Flutter desktop UI startup
- global command chat submission through the UI
- same-thread chat composer submission through the UI
- deterministic model `create_task` tool call through the harness and memory
  MCP service
- Backlog rendering of the task created by the tool call

CI already installs Xvfb and the Linux desktop build packages before running
this suite. The local setup above mirrors that environment closely enough to run
the same rendered UI test on a developer workstation or headless Linux host.
