= Remote Docker Runtime
:description: Build and run the remote Agent Awesome runtime container.

This folder contains the Docker runtime boundary for remote Agent Awesome hosts.
The container starts memory, runbook/Launchpad, harness, and gateway processes,
then exposes only the gateway port. The desktop UI connects to that gateway
with local service auto-start disabled.

== Build

[source,sh]
----
docker build -f deploy/docker/Dockerfile -t agent-awesome/remote-runtime .
----

== Run

Create persistent folders on the remote host and copy the Gemma model there:

[source,sh]
----
mkdir -p /srv/agent-awesome/data /srv/agent-awesome/logs /srv/agent-awesome/models
scp /local/path/gemma.gguf remote:/srv/agent-awesome/models/gemma.gguf
----

Run the container behind your HTTPS reverse proxy or cloud load balancer:

[source,sh]
----
docker run --rm \
  --name agent-awesome \
  -p 8070:8070 \
  -e AGENTAWESOME_GATEWAY_TOKEN="$AGENTAWESOME_GATEWAY_TOKEN" \
  -e AA_GATEWAY_PUBLIC_BASE_URL="https://agent.example.com/api" \
  -e AA_LOCAL_MODEL_PATH="/models/gemma.gguf" \
  -e AA_LOCAL_MODEL_CHAT_URL="http://127.0.0.1:11667/v1/chat/completions" \
  -e AA_LOCAL_MODEL_NAME="gemma" \
  -v /srv/agent-awesome/data:/var/lib/agent-awesome \
  -v /srv/agent-awesome/logs:/var/log/agent-awesome \
  -v /srv/agent-awesome/models:/models:ro \
  agent-awesome/remote-runtime
----

`AA_LOCAL_MODEL_PATH` starts a mounted `llama-server` executable when one is
available in the image or on `PATH`. If the model is served by another process,
omit `AA_LOCAL_MODEL_PATH` and point `AA_LOCAL_MODEL_CHAT_URL` at that
OpenAI-compatible endpoint.

== UI Profile

Use `deploy/docker/ui-runtime.remote-gateway.json` as the desktop runtime
profile template. Launch the UI with:

[source,sh]
----
flutter run -d linux \
  --dart-define=AUTO_START_LOCAL_SERVICES=false \
  --dart-define=AGENTAWESOME_RUNTIME_PROFILE=/home/doug/dev/agentawesome/agent/deploy/docker/ui-runtime.remote-gateway.json \
  --dart-define=AGENT_GATEWAY_BASE_URL=https://agent.example.com/api \
  --dart-define=AGENTAWESOME_GATEWAY_TOKEN="$AGENTAWESOME_GATEWAY_TOKEN"
----

This keeps the UI on the laptop while all memory, tool, agent, workflow, and
Launchpad calls go through the remote gateway.

== Queue Worker

Run one Launchpad queue tick from cron on the remote host:

[source,cron]
----
*/5 * * * * docker exec agent-awesome runbook-service queue-worker --gateway-base-url http://127.0.0.1:8070/api --gateway-token "$AGENTAWESOME_GATEWAY_TOKEN" --target-id this_computer
----

The worker recovers expired leases, enqueues due Launchpad schedules, leases
one matching queued run, starts it through the gateway, waits for terminal
runbook status, and releases the queue item as completed, failed, or canceled.

== UI-Generated Bundle

The Settings app header includes remote Docker actions. They write the active
runtime's selected agent, tool, model, runbook files, and selected llama.cpp
server binary under:

[source,text]
----
build/remote-runtime/<profile-id>
----

Use the generated `Dockerfile` path in that folder to build an image from the
workspace root. The generated `runtime-profile.json` is the matching desktop UI
profile for the remote gateway, and the generated scripts can build the image,
run it locally, or load it onto an SSH-accessible Docker host.

== Smoke Tests

Run the route-level Docker smoke from the workspace root:

[source,sh]
----
scripts/smoke-remote-runtime.sh
----

Run the Docker smoke plus the Flutter controller live path:

[source,sh]
----
scripts/smoke-ui-remote-runtime.sh
----

The UI smoke builds a temporary configured image, starts the gateway container,
loads a remote desktop profile, creates a chat session, then creates, previews,
starts, and snapshots a Launchpad run through the gateway.

Run the same UI smoke with a real Gemma chat turn by providing the local model:

[source,sh]
----
AA_LOCAL_GEMMA_MODEL=/local/path/gemma.gguf \
AA_LLAMA_SERVER_LOCAL=/local/path/llama-server \
scripts/smoke-ui-remote-model-runtime.sh
----

`AA_LLAMA_SERVER_LOCAL` may be omitted when `llama-server` is already on
`PATH`. This mode copies the server binary into the image, mounts the model
read-only, sends a desktop UI chat message through the remote gateway, and
asserts that the model response includes `remote gemma ready`.

When you want to prove the same UI-to-gateway-to-harness chat path without a
large model file, run the deterministic OpenAI-compatible smoke:

[source,sh]
----
scripts/smoke-ui-remote-mock-model-runtime.sh
----

That smoke starts a tiny local chat-completions endpoint, runs the container
with host networking so the endpoint is still loopback-only to the harness, and
asserts the same desktop UI chat response.
