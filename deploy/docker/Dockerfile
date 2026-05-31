# Builds the Agent Awesome remote runtime image for cloud or server hosts.
FROM golang:1.26-bookworm AS build

WORKDIR /src

COPY platform ./platform
COPY harness ./harness
COPY gateway ./gateway
COPY memory ./memory

RUN cd harness && go build -trimpath -buildvcs=false -o /out/agent-awesome ./cmd/agent-awesome
RUN cd harness && go build -trimpath -buildvcs=false -o /out/runbook-service ./cmd/runbook-service
RUN cd gateway && go build -trimpath -buildvcs=false -o /out/agent-gateway ./cmd/agent-gateway
RUN cd memory && go build -trimpath -buildvcs=false -o /out/memoryd ./cmd/memoryd

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agent-awesome

COPY --from=build /out/agent-awesome /usr/local/bin/agent-awesome
COPY --from=build /out/runbook-service /usr/local/bin/runbook-service
COPY --from=build /out/agent-gateway /usr/local/bin/agent-gateway
COPY --from=build /out/memoryd /usr/local/bin/memoryd
COPY harness/agent.yaml /opt/agent-awesome/config/agent.yaml
COPY harness/tool.local.yaml /opt/agent-awesome/config/tool.yaml
COPY deploy/docker/config/model.local-gemma.yaml /opt/agent-awesome/config/model.yaml
COPY deploy/docker/entrypoint.sh /usr/local/bin/agent-awesome-container

RUN chmod +x /usr/local/bin/agent-awesome-container \
    && mkdir -p /var/lib/agent-awesome /var/log/agent-awesome

EXPOSE 8070

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:8070/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/agent-awesome-container"]
