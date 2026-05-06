// This Worker fronts the Agent Awesome pilot container for Slack-only HTTP traffic.
import { Container, getContainer } from "@cloudflare/containers";
import { env as workerEnv } from "cloudflare:workers";

const slackSignatureVersion = "v0";
const slackTimestampWindowSeconds = 60 * 5;

/** Env describes Worker bindings, vars, and secrets used by the pilot. */
export interface Env {
  AGENT_AWESOME_CONTAINER: DurableObjectNamespace<AgentAwesomeContainer>;
  CONTEXT_SNAPSHOTS: R2Bucket;
  AGENTAWESOME_APP_NAME?: string;
  AGENTAWESOME_USER_ID?: string;
  AGENTAWESOME_GATEWAY_TOKEN?: string;
  AGENTAWESOME_CONTEXT_API_BASE_URL?: string;
  AGENTAWESOME_PERSISTENCE_TOKEN?: string;
  AGENTAWESOME_MEMORY_SNAPSHOT_URL?: string;
  AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT?: string;
  AGENTAWESOME_SERVICE_START_TIMEOUT?: string;
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

/** AgentAwesomeContainer configures the Linux container that runs the Go services. */
export class AgentAwesomeContainer extends Container {
  defaultPort = 8070;
  requiredPorts = [8070];
  sleepAfter = "30m";
  envVars = buildContainerEnv(workerEnv as Env);

  /** onStart records container startup in Cloudflare observability logs. */
  override onStart(): void {
    console.log("Agent Awesome pilot container started");
  }

  /** onStop records container shutdown details in Cloudflare observability logs. */
  override onStop(params: { exitCode?: number; reason?: string }): void {
    console.log("Agent Awesome pilot container stopped", params);
  }

  /** onError logs startup and readiness failures before rethrowing them. */
  override onError(error: unknown): never {
    console.error("Agent Awesome pilot container error", error);
    throw error;
  }
}

/** buildContainerEnv maps Worker vars and secrets into process env variables. */
export function buildContainerEnv(env: Env): Record<string, string> {
  return {
    AGENTAWESOME_APP_NAME: env.AGENTAWESOME_APP_NAME ?? "personal_pilot",
    AGENTAWESOME_USER_ID: env.AGENTAWESOME_USER_ID ?? "doug",
    AGENTAWESOME_GATEWAY_TOKEN: env.AGENTAWESOME_GATEWAY_TOKEN ?? "",
    AGENTAWESOME_CONTEXT_API_BASE_URL:
      env.AGENTAWESOME_CONTEXT_API_BASE_URL ??
      "http://127.0.0.1:8081/api/context",
    AGENTAWESOME_PERSISTENCE_TOKEN: env.AGENTAWESOME_PERSISTENCE_TOKEN ?? "",
    AGENTAWESOME_MEMORY_SNAPSHOT_URL:
      env.AGENTAWESOME_MEMORY_SNAPSHOT_URL ??
      "https://agent-awesome.com/internal/context-snapshot",
    AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT:
      env.AGENTAWESOME_GATEWAY_REQUEST_TIMEOUT ?? "10m",
    AGENTAWESOME_SERVICE_START_TIMEOUT:
      env.AGENTAWESOME_SERVICE_START_TIMEOUT ?? "45s",
    SLACK_ENABLED: env.SLACK_ENABLED ?? "true",
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

/** routeRequest forwards authorized frontend and Slack traffic to the container. */
export async function routeRequest(
  request: Request,
  env: Env,
): Promise<Response> {
  const persistenceResponse = await handlePersistenceRequest(request, env);
  if (persistenceResponse !== null) {
    return persistenceResponse;
  }
  if (isGatewayRequest(request) && hasGatewayAuth(request, env)) {
    return getContainer(env.AGENT_AWESOME_CONTAINER, "personal-pilot").fetch(
      request,
    );
  }
  const signedBody = await readSignedSlackBody(request, env);
  if (signedBody === null) {
    return new Response("Not found\n", { status: 404 });
  }
  return getContainer(env.AGENT_AWESOME_CONTAINER, "personal-pilot").fetch(
    rebuildRequest(request, signedBody),
  );
}

/** isGatewayRequest reports whether a request targets the gateway control plane. */
function isGatewayRequest(request: Request): boolean {
  const pathname = new URL(request.url).pathname;
  return pathname === "/mcp" || pathname.startsWith("/api/");
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
): Promise<string | null> {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.pathname !== "/slack/events") {
    return null;
  }
  const timestamp = request.headers.get("x-slack-request-timestamp");
  const signature = request.headers.get("x-slack-signature");
  if (
    env.SLACK_SIGNING_SECRET === undefined ||
    timestamp === null ||
    signature === null ||
    !isFreshSlackTimestamp(timestamp)
  ) {
    return null;
  }
  const body = await request.text();
  if (
    !(await hasValidSlackSignature(
      env.SLACK_SIGNING_SECRET,
      timestamp,
      body,
      signature,
    ))
  ) {
    return null;
  }
  return body;
}

/** handlePersistenceRequest serves the private R2-backed context snapshot endpoint. */
async function handlePersistenceRequest(
  request: Request,
  env: Env,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== "/internal/context-snapshot") {
    return null;
  }
  if (!hasPersistenceAuth(request, env)) {
    return new Response("Not found\n", { status: 404 });
  }
  switch (request.method) {
    case "GET":
      return readContextSnapshot(env);
    case "PUT":
      return writeContextSnapshot(request, env);
    default:
      return new Response("Not found\n", { status: 404 });
  }
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
async function readContextSnapshot(env: Env): Promise<Response> {
  const object = await env.CONTEXT_SNAPSHOTS.get(contextSnapshotKey());
  if (object === null) {
    return new Response("Not found\n", { status: 404 });
  }
  return new Response(object.body, {
    headers: {
      "Content-Type": object.httpMetadata?.contentType ?? "application/gzip",
      ETag: object.etag,
    },
  });
}

/** writeContextSnapshot stores one memory snapshot in R2. */
async function writeContextSnapshot(
  request: Request,
  env: Env,
): Promise<Response> {
  await env.CONTEXT_SNAPSHOTS.put(contextSnapshotKey(), request.body, {
    httpMetadata: {
      contentType: request.headers.get("content-type") ?? "application/gzip",
    },
  });
  return new Response(null, { status: 204 });
}

/** contextSnapshotKey returns the canonical R2 object key for this pilot. */
function contextSnapshotKey(): string {
  return "personal-pilot/context-snapshot.tar.gz";
}

/** rebuildRequest restores the raw Slack body after signature verification reads it. */
function rebuildRequest(request: Request, body: string): Request {
  const headers = new Headers(request.headers);
  headers.delete("content-length");
  return new Request(request.url, {
    body,
    headers,
    method: request.method,
    redirect: request.redirect,
  });
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
  body: string,
  signature: string,
): Promise<boolean> {
  const expected = await slackSignature(signingSecret, timestamp, body);
  return constantTimeEqual(expected, signature);
}

/** slackSignature computes the hex digest Slack expects for one request body. */
async function slackSignature(
  signingSecret: string,
  timestamp: string,
  body: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${slackSignatureVersion}:${timestamp}:${body}`),
  );
  return `${slackSignatureVersion}=${hexEncode(new Uint8Array(digest))}`;
}

/** hexEncode renders bytes as lowercase hexadecimal text. */
function hexEncode(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** constantTimeEqual compares same-length strings without data-dependent exits. */
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

export default {
  /** fetch handles Worker HTTP requests and delegates service routes to the container. */
  fetch(request: Request, env: Env): Promise<Response> {
    return routeRequest(request, env);
  },
} satisfies ExportedHandler<Env>;
