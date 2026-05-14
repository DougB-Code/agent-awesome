// This file contains testable Worker routing, auth, and persistence behavior.

const slackSignatureVersion = "v0";
const slackTimestampWindowSeconds = 60 * 5;

/** gatewayPort is the container port served by agent-gateway. */
export const gatewayPort = 8070;

/** containerName is the stable Durable Object instance for the beta pilot. */
export const containerName = "beta-pilot";

/** containerPortReadyTimeoutMS is the maximum Worker wait for gateway readiness. */
export const containerPortReadyTimeoutMS = 90_000;

/** Env describes Worker vars and bindings used outside the Container class. */
export interface Env {
  CONTEXT_SNAPSHOTS: R2Bucket;
  AGENTAWESOME_APP_NAME?: string;
  AGENTAWESOME_USER_ID?: string;
  AGENTAWESOME_GATEWAY_TOKEN?: string;
  AGENTAWESOME_CONTEXT_API_BASE_URL?: string;
  AGENTAWESOME_CONTEXT_API_TOKEN?: string;
  AGENTAWESOME_MEMORY_DOMAINS_JSON?: string;
  AGENTAWESOME_MEMORY_POLICY_JSON?: string;
  AGENTAWESOME_MEMORY_SERVICES_JSON?: string;
  AGENTAWESOME_AGENT_PROFILES_JSON?: string;
  AGENTAWESOME_PERSISTENCE_TOKEN?: string;
  AGENTAWESOME_MEMORY_SNAPSHOT_URL?: string;
  AGENTAWESOME_MEMORY_SNAPSHOT_PREFIX?: string;
  AGENTAWESOME_MODEL_PROVIDER_ID?: string;
  AGENTAWESOME_MODEL_ID?: string;
  AGENTAWESOME_GATEWAY_LOG_FILE?: string;
  AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT?: string;
  AGENTAWESOME_SERVICE_START_TIMEOUT?: string;
  AGENTAWESOME_SLACK_READ_ONLY_TOOLS?: string;
  SLACK_ENABLED?: string;
  SLACK_SOCKET_MODE?: string;
  SLACK_SIGNING_SECRET?: string;
  SLACK_BOT_TOKEN?: string;
  SLACK_APP_TOKEN?: string;
  SLACK_ALLOWED_TEAM_ID?: string;
  SLACK_ALLOWED_USER_ID?: string;
  SLACK_ALLOWED_CHANNEL_ID?: string;
  OPENAI_API_KEY?: string;
}

/** RouteDependencies injects edge runtime hooks for production and tests. */
export interface RouteDependencies<TEnv extends Env> {
  fetchGateway(request: Request, env: TEnv): Promise<Response>;
  waitUntil?(promise: Promise<unknown>): void;
}

/** buildContainerEnv maps Worker vars and secrets into process env variables. */
export function buildContainerEnv(env: Env): Record<string, string> {
  return {
    AGENTAWESOME_APP_NAME: env.AGENTAWESOME_APP_NAME ?? "agent_awesome",
    AGENTAWESOME_USER_ID: env.AGENTAWESOME_USER_ID ?? "doug",
    AGENTAWESOME_GATEWAY_TOKEN: env.AGENTAWESOME_GATEWAY_TOKEN ?? "",
    AGENTAWESOME_CONTEXT_API_BASE_URL:
      env.AGENTAWESOME_CONTEXT_API_BASE_URL ??
      "http://127.0.0.1:8081/api/context",
    AGENTAWESOME_CONTEXT_API_TOKEN: env.AGENTAWESOME_CONTEXT_API_TOKEN ?? "",
    AGENTAWESOME_MEMORY_DOMAINS_JSON:
      env.AGENTAWESOME_MEMORY_DOMAINS_JSON ?? defaultMemoryDomainsJSON(),
    AGENTAWESOME_MEMORY_POLICY_JSON:
      env.AGENTAWESOME_MEMORY_POLICY_JSON ?? defaultMemoryPolicyJSON(),
    AGENTAWESOME_MEMORY_SERVICES_JSON:
      env.AGENTAWESOME_MEMORY_SERVICES_JSON ?? defaultMemoryServicesJSON(env),
    AGENTAWESOME_AGENT_PROFILES_JSON:
      env.AGENTAWESOME_AGENT_PROFILES_JSON ?? defaultAgentProfilesJSON(env),
    AGENTAWESOME_PERSISTENCE_TOKEN: env.AGENTAWESOME_PERSISTENCE_TOKEN ?? "",
    AGENTAWESOME_MEMORY_SNAPSHOT_URL:
      env.AGENTAWESOME_MEMORY_SNAPSHOT_URL ??
      "https://agent-awesome.com/internal/context-snapshot",
    AGENTAWESOME_MODEL_PROVIDER_ID: env.AGENTAWESOME_MODEL_PROVIDER_ID ?? "openai",
    AGENTAWESOME_MODEL_ID: env.AGENTAWESOME_MODEL_ID ?? "gpt-5.4-mini",
    AGENTAWESOME_GATEWAY_LOG_FILE:
      env.AGENTAWESOME_GATEWAY_LOG_FILE ?? "/app/logs/gateway.log",
    AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT:
      env.AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT ?? "10m",
    AGENTAWESOME_SERVICE_START_TIMEOUT:
      env.AGENTAWESOME_SERVICE_START_TIMEOUT ?? "45s",
    AGENTAWESOME_SLACK_READ_ONLY_TOOLS:
      env.AGENTAWESOME_SLACK_READ_ONLY_TOOLS ?? env.SLACK_ENABLED ?? "false",
    SLACK_ENABLED: env.SLACK_ENABLED ?? "false",
    SLACK_SOCKET_MODE: env.SLACK_SOCKET_MODE ?? "false",
    SLACK_SIGNING_SECRET: env.SLACK_SIGNING_SECRET ?? "",
    SLACK_BOT_TOKEN: env.SLACK_BOT_TOKEN ?? "",
    SLACK_APP_TOKEN: env.SLACK_APP_TOKEN ?? "",
    SLACK_ALLOWED_TEAM_ID: env.SLACK_ALLOWED_TEAM_ID ?? "",
    SLACK_ALLOWED_USER_ID: env.SLACK_ALLOWED_USER_ID ?? "",
    SLACK_ALLOWED_CHANNEL_ID: env.SLACK_ALLOWED_CHANNEL_ID ?? "",
    OPENAI_API_KEY: env.OPENAI_API_KEY ?? "",
  };
}

/** routeRequest forwards authorized health, control-plane, and Slack traffic. */
export async function routeRequest<TEnv extends Env>(
  request: Request,
  env: TEnv,
  dependencies: RouteDependencies<TEnv>,
): Promise<Response> {
  const persistenceResponse = await handlePersistenceRequest(request, env);
  if (persistenceResponse !== null) {
    return persistenceResponse;
  }
  if (isHealthRequest(request)) {
    return dependencies.fetchGateway(request, env);
  }
  if (isGatewayRequest(request) && hasGatewayAuth(request, env)) {
    return dependencies.fetchGateway(request, env);
  }
  const signedBody = await readSignedSlackBody(request, env);
  if (signedBody.body === null) {
    if (new URL(request.url).pathname === "/slack/events") {
      console.warn("Slack request rejected before container", {
        reason: signedBody.reason,
        method: request.method,
      });
    }
    return new Response("Not found\n", { status: 404 });
  }
  console.log("Slack request verified by Worker");
  const challenge = slackURLVerificationChallenge(signedBody.body);
  if (challenge !== null) {
    return new Response(challenge, {
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      status: 200,
    });
  }
  const slackRequest = rebuildRequest(request, signedBody.body);
  if (dependencies.waitUntil !== undefined) {
    dependencies.waitUntil(forwardSlackRequest(slackRequest, env, dependencies));
    return new Response("OK\n", { status: 200 });
  }
  return dependencies.fetchGateway(slackRequest, env);
}

/** isHealthRequest reports whether the request targets public liveness. */
function isHealthRequest(request: Request): boolean {
  const pathname = new URL(request.url).pathname;
  return (
    pathname === "/healthz" &&
    (request.method === "GET" || request.method === "HEAD")
  );
}

/** isGatewayRequest reports whether a request targets the gateway control plane. */
function isGatewayRequest(request: Request): boolean {
  const pathname = new URL(request.url).pathname;
  return pathname === "/mcp" || pathname.startsWith("/mcp/") || pathname.startsWith("/api/");
}

/** defaultMemoryDomainsJSON returns the shipped beta cloud domain topology. */
function defaultMemoryDomainsJSON(): string {
  return JSON.stringify([
    {
      id: "doug",
      label: "Doug Memory",
      endpoint: "http://127.0.0.1:8090/mcp",
      health_url: "http://127.0.0.1:8090/healthz",
    },
    {
      id: "family",
      label: "Family Memory",
      endpoint: "http://127.0.0.1:8091/mcp",
      health_url: "http://127.0.0.1:8091/healthz",
    },
  ]);
}

/** defaultMemoryPolicyJSON returns the operator default profile grants. */
function defaultMemoryPolicyJSON(): string {
  return JSON.stringify({
    actor: "agent:doug",
    read_domains: ["doug"],
    write_domains: ["doug"],
    default_write_domain: "doug",
    allowed_sensitivities: ["public", "internal", "private"],
  });
}

/** defaultAgentProfilesJSON returns the shipped beta profile registry. */
function defaultAgentProfilesJSON(env: Env): string {
  const appName = env.AGENTAWESOME_APP_NAME ?? "agent_awesome";
  return JSON.stringify([
    {
      id: "doug",
      label: "Doug",
      app_name: appName,
      user_id: "doug",
      harness_base_url: "http://127.0.0.1:8080/api",
      context_base_url: "http://127.0.0.1:8081/api/context",
      actor: "agent:doug",
      read_domains: ["doug"],
      write_domains: ["doug"],
      default_write_domain: "doug",
      allowed_sensitivities: ["public", "internal", "private"],
    },
    {
      id: "family",
      label: "Family",
      app_name: appName,
      user_id: "family",
      harness_base_url: "http://127.0.0.1:8082/api",
      context_base_url: "http://127.0.0.1:8083/api/context",
      actor: "agent:family",
      read_domains: ["family"],
      write_domains: ["family"],
      default_write_domain: "family",
      allowed_sensitivities: ["public", "internal", "private"],
    },
  ]);
}

/** defaultMemoryServicesJSON returns the shipped beta service config. */
function defaultMemoryServicesJSON(env: Env): string {
  return JSON.stringify([
    {
      domain_id: "doug",
      name: "memory-doug",
      health_url: "http://127.0.0.1:8090/healthz",
      command: "/usr/local/bin/memoryd",
      arguments: [
        "--addr",
        "127.0.0.1:8090",
        "--db",
        "/app/data/memory/doug/memory.db",
        "--data",
        "/app/data/memory/doug/files",
        "--log-file",
        "/app/logs/memory-doug.log",
        "--snapshot-url",
        memorySnapshotURL(env, "doug"),
      ],
      auto_start: true,
    },
    {
      domain_id: "family",
      name: "memory-family",
      health_url: "http://127.0.0.1:8091/healthz",
      command: "/usr/local/bin/memoryd",
      arguments: [
        "--addr",
        "127.0.0.1:8091",
        "--db",
        "/app/data/memory/family/memory.db",
        "--data",
        "/app/data/memory/family/files",
        "--log-file",
        "/app/logs/memory-family.log",
        "--snapshot-url",
        memorySnapshotURL(env, "family"),
      ],
      auto_start: true,
    },
  ]);
}

/** memorySnapshotURL returns the private Worker snapshot URL for one domain. */
function memorySnapshotURL(env: Env, domainID: string): string {
  const base =
    env.AGENTAWESOME_MEMORY_SNAPSHOT_URL ??
    "https://agent-awesome.com/internal/context-snapshot";
  return `${base.replace(/\/+$/, "")}/${domainID}`;
}

/** hasGatewayAuth checks the gateway bearer token before reaching the container. */
function hasGatewayAuth(request: Request, env: Env): boolean {
  const token = env.AGENTAWESOME_GATEWAY_TOKEN ?? "";
  if (token === "") {
    return false;
  }
  return constantTimeEqual(
    request.headers.get("authorization") ?? "",
    `Bearer ${token}`,
  );
}

/** readSignedSlackBody returns the verified raw body for an allowed Slack request. */
async function readSignedSlackBody(
  request: Request,
  env: Env,
): Promise<{ body: ArrayBuffer | null; reason: string }> {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.pathname !== "/slack/events") {
    return { body: null, reason: "not Slack events path" };
  }
  const timestamp = request.headers.get("x-slack-request-timestamp");
  const signature = request.headers.get("x-slack-signature");
  if (env.SLACK_SIGNING_SECRET === undefined || env.SLACK_SIGNING_SECRET === "") {
    return { body: null, reason: "missing signing secret" };
  }
  if (timestamp === null) {
    return { body: null, reason: "missing timestamp" };
  }
  if (signature === null) {
    return { body: null, reason: "missing signature" };
  }
  if (!isFreshSlackTimestamp(timestamp)) {
    return { body: null, reason: "stale timestamp" };
  }
  const body = await request.arrayBuffer();
  if (
    !(await hasValidSlackSignature(
      env.SLACK_SIGNING_SECRET,
      timestamp,
      body,
      signature,
    ))
  ) {
    return { body: null, reason: "invalid signature" };
  }
  return { body, reason: "verified" };
}

/** handlePersistenceRequest serves the private R2-backed context snapshot endpoint. */
async function handlePersistenceRequest(
  request: Request,
  env: Env,
): Promise<Response | null> {
  const url = new URL(request.url);
  const domainID = snapshotDomainFromPath(url.pathname);
  if (domainID === null) {
    return null;
  }
  if (!hasPersistenceAuth(request, env)) {
    return new Response("Not found\n", { status: 404 });
  }
  switch (request.method) {
    case "GET":
      return readContextSnapshot(env, domainID);
    case "HEAD":
      return headContextSnapshot(env, domainID);
    case "PUT":
      return writeContextSnapshot(request, env, domainID);
    default:
      return new Response("Not found\n", { status: 404 });
  }
}

/** snapshotDomainFromPath parses the optional memory domain from a snapshot route. */
function snapshotDomainFromPath(pathname: string): string | null {
  const base = "/internal/context-snapshot";
  if (!pathname.startsWith(`${base}/`)) {
    return null;
  }
  const domainID = pathname.slice(base.length + 1);
  if (!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(domainID)) {
    return null;
  }
  return domainID;
}

/** hasPersistenceAuth checks the private bearer token for container snapshots. */
function hasPersistenceAuth(request: Request, env: Env): boolean {
  const token = env.AGENTAWESOME_PERSISTENCE_TOKEN ?? "";
  if (token === "") {
    return false;
  }
  return constantTimeEqual(
    request.headers.get("authorization") ?? "",
    `Bearer ${token}`,
  );
}

/** readContextSnapshot returns the latest persisted memory snapshot from R2. */
async function readContextSnapshot(env: Env, domainID: string): Promise<Response> {
  const object = await env.CONTEXT_SNAPSHOTS.get(contextSnapshotKey(env, domainID));
  if (object === null) {
    return new Response("Not found\n", { status: 404 });
  }
  return new Response(object.body, {
    headers: snapshotHeaders(object),
  });
}

/** headContextSnapshot returns latest snapshot metadata without the archive body. */
async function headContextSnapshot(env: Env, domainID: string): Promise<Response> {
  const object = await env.CONTEXT_SNAPSHOTS.head(contextSnapshotKey(env, domainID));
  if (object === null) {
    return new Response(null, { status: 404 });
  }
  return new Response(null, { headers: snapshotHeaders(object) });
}

/** writeContextSnapshot stores one memory snapshot in R2. */
async function writeContextSnapshot(
  request: Request,
  env: Env,
  domainID: string,
): Promise<Response> {
  await env.CONTEXT_SNAPSHOTS.put(contextSnapshotKey(env, domainID), request.body, {
    httpMetadata: {
      contentType: request.headers.get("content-type") ?? "application/gzip",
    },
  });
  return new Response(null, { status: 204 });
}

/** contextSnapshotKey returns the configured R2 object key for this agent. */
function contextSnapshotKey(env: Env, domainID: string): string {
  const prefix =
    env.AGENTAWESOME_MEMORY_SNAPSHOT_PREFIX ??
    "beta-pilot/memory";
  return `${prefix.replace(/^\/+|\/+$/g, "")}/${domainID}/context-snapshot.tar.gz`;
}

/** snapshotHeaders returns safe operator metadata for a persisted snapshot. */
function snapshotHeaders(object: R2Object | R2ObjectBody): Headers {
  const headers = new Headers();
  headers.set(
    "Content-Type",
    object.httpMetadata?.contentType ?? "application/gzip",
  );
  headers.set("ETag", object.etag);
  headers.set("Content-Length", object.size.toString());
  headers.set("Last-Modified", object.uploaded.toUTCString());
  return headers;
}

/** rebuildRequest restores the raw Slack body after signature verification reads it. */
function rebuildRequest(request: Request, body: ArrayBuffer): Request {
  const headers = new Headers(request.headers);
  headers.delete("content-length");
  return new Request(request.url, {
    body,
    headers,
    method: request.method,
    redirect: request.redirect,
  });
}

/** slackURLVerificationChallenge extracts Slack's install-time challenge response. */
function slackURLVerificationChallenge(body: ArrayBuffer): string | null {
  try {
    const payload = JSON.parse(new TextDecoder().decode(body));
    if (
      payload !== null &&
      typeof payload === "object" &&
      "type" in payload &&
      payload.type === "url_verification" &&
      "challenge" in payload &&
      typeof payload.challenge === "string"
    ) {
      return payload.challenge;
    }
  } catch {
    return null;
  }
  return null;
}

/** forwardSlackRequest sends a verified Slack request to the container asynchronously. */
async function forwardSlackRequest<TEnv extends Env>(
  request: Request,
  env: TEnv,
  dependencies: RouteDependencies<TEnv>,
): Promise<void> {
  try {
    const response = await dependencies.fetchGateway(request, env);
    await response.arrayBuffer();
    console.log("Slack request forwarded to gateway", {
      status: response.status,
      statusText: response.statusText,
    });
    if (!response.ok) {
      console.error("Slack request forwarding failed", {
        status: response.status,
        statusText: response.statusText,
      });
    }
  } catch (error) {
    console.error("Slack request forwarding failed", error);
  }
}

/** isFreshSlackTimestamp rejects old signed requests that could be replayed. */
function isFreshSlackTimestamp(timestamp: string): boolean {
  const seconds = Number.parseInt(timestamp, 10);
  if (!Number.isFinite(seconds)) {
    return false;
  }
  return Math.abs(Date.now() / 1000 - seconds) <= slackTimestampWindowSeconds;
}

/** hasValidSlackSignature verifies Slack's v0 HMAC signature. */
async function hasValidSlackSignature(
  signingSecret: string,
  timestamp: string,
  body: ArrayBuffer,
  signature: string,
): Promise<boolean> {
  const expected = await slackSignature(signingSecret, timestamp, body);
  return constantTimeEqual(expected, signature);
}

/** slackSignature computes the hex digest Slack expects for one request body. */
async function slackSignature(
  signingSecret: string,
  timestamp: string,
  body: ArrayBuffer,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const prefix = encoder.encode(`${slackSignatureVersion}:${timestamp}:`);
  const message = concatBytes(prefix, new Uint8Array(body));
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    message,
  );
  return `${slackSignatureVersion}=${hexEncode(new Uint8Array(digest))}`;
}

/** concatBytes joins byte slices without decoding the signed body. */
function concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
  const output = new Uint8Array(left.byteLength + right.byteLength);
  output.set(left, 0);
  output.set(right, left.byteLength);
  return output;
}

/** hexEncode renders bytes as lowercase hexadecimal text. */
function hexEncode(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** constantTimeEqual compares strings without data-dependent early returns. */
function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  const length = Math.max(leftBytes.length, rightBytes.length);
  let diff = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < length; index++) {
    diff |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return diff === 0;
}
