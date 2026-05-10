// This file verifies the Cloudflare Worker deploy surface without live Cloudflare access.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { webcrypto } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const workerRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const buildDir = resolve(workerRoot, "../../../build/cloudflare-worker/smoke");

if (globalThis.crypto === undefined) {
  Object.defineProperty(globalThis, "crypto", { value: webcrypto });
}

/** main runs the build, configuration, and routing smoke checks. */
async function main() {
  mkdirSync(buildDir, { recursive: true });
  assertRequiredDeploymentAssets();
  assertPackageScripts();
  assertTypeScriptCoverage(parseTSConfig());
  runLocalBin("tsc", ["--noEmit"]);
  runLocalBin("esbuild", [
    "src/index.ts",
    "--bundle",
    "--format=esm",
    "--platform=neutral",
    "--target=es2022",
    `--outfile=${resolve(buildDir, "index.mjs")}`,
    "--external:cloudflare:workers",
    "--external:@cloudflare/containers",
  ]);
  runLocalBin("esbuild", [
    "src/app.ts",
    "--bundle",
    "--format=esm",
    "--platform=neutral",
    "--target=es2022",
    `--outfile=${resolve(buildDir, "app.mjs")}`,
  ]);

  assertContainerConfiguration(parseWranglerConfig());
  const app = await import(pathToFileURL(resolve(buildDir, "app.mjs")).href);
  assertContainerEnvironment(app);
  await assertHealthzWorks(app);
  await assertMCPAuthBoundary(app);
  await assertSnapshotHeadMetadata(app);
  await assertSlackIngressReachesGateway(app);
  console.log("Cloudflare Worker smoke test passed.");
}

/** assertRequiredDeploymentAssets verifies the Worker and Container files ship together. */
function assertRequiredDeploymentAssets() {
  for (const path of [
    resolve(workerRoot, "src/index.ts"),
    resolve(workerRoot, "src/app.ts"),
    resolve(workerRoot, "scripts/smoke-test.mjs"),
    resolve(workerRoot, "../../../Dockerfile.cloudflare"),
  ]) {
    assert.ok(existsSync(path), `${path} must exist`);
  }
}

/** assertPackageScripts verifies package.json points to shipped check files. */
function assertPackageScripts() {
  const packageJSON = JSON.parse(readFileSync(resolve(workerRoot, "package.json"), "utf8"));
  assert.equal(packageJSON.scripts?.smoke, "node scripts/smoke-test.mjs");
  assert.equal(packageJSON.scripts?.test, "npm run smoke");
  assert.equal(packageJSON.scripts?.check, "tsc --noEmit");
  assert.ok(
    existsSync(resolve(workerRoot, packageJSON.scripts.smoke.replace("node ", ""))),
    "smoke script must point to an existing file",
  );
}

/** assertTypeScriptCoverage verifies tsconfig includes all Worker source files. */
function assertTypeScriptCoverage(config) {
  assert.deepEqual(config.include, ["src/**/*.ts"]);
  const sourceFiles = sourceTSFiles(resolve(workerRoot, "src"));
  assert.ok(sourceFiles.includes(resolve(workerRoot, "src/index.ts")), "src/index.ts must be covered");
  assert.ok(sourceFiles.includes(resolve(workerRoot, "src/app.ts")), "src/app.ts must be covered");
}

/** sourceTSFiles recursively lists Worker TypeScript source files. */
function sourceTSFiles(root) {
  const files = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = resolve(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...sourceTSFiles(path));
    } else if (entry.isFile() && entry.name.endsWith(".ts")) {
      files.push(path);
    }
  }
  return files;
}

/** runLocalBin executes one package binary and fails on nonzero exit status. */
function runLocalBin(name, args) {
  const executable = resolve(
    workerRoot,
    "node_modules/.bin",
    process.platform === "win32" ? `${name}.cmd` : name,
  );
  const result = spawnSync(executable, args, {
    cwd: workerRoot,
    stdio: "inherit",
  });
  if (result.status !== 0) {
    throw new Error(`${name} failed with status ${result.status}`);
  }
}

/** parseWranglerConfig reads wrangler.jsonc with TypeScript's JSONC parser. */
function parseWranglerConfig() {
  const configPath = resolve(workerRoot, "wrangler.jsonc");
  const source = readFileSync(configPath, "utf8");
  const parsed = ts.parseConfigFileTextToJson(configPath, source);
  if (parsed.error !== undefined) {
    throw new Error(ts.flattenDiagnosticMessageText(parsed.error.messageText, "\n"));
  }
  return parsed.config;
}

/** parseTSConfig reads tsconfig.json with TypeScript's JSONC parser. */
function parseTSConfig() {
  const configPath = resolve(workerRoot, "tsconfig.json");
  const source = readFileSync(configPath, "utf8");
  const parsed = ts.parseConfigFileTextToJson(configPath, source);
  if (parsed.error !== undefined) {
    throw new Error(ts.flattenDiagnosticMessageText(parsed.error.messageText, "\n"));
  }
  return parsed.config;
}

/** assertContainerConfiguration proves the Worker route and Container bindings exist. */
function assertContainerConfiguration(config) {
  assert.equal(config.main, "src/index.ts");
  assert.equal(config.workers_dev, false);
  assert.ok(
    config.routes?.some((route) => route.pattern === "agent-awesome.com/*"),
    "agent-awesome.com route must be configured",
  );
  const container = exactlyOne(config.containers, "container");
  assert.equal(container.class_name, "AgentAwesomeContainer");
  assert.equal(container.image, "../../../Dockerfile.cloudflare");
  assert.equal(container.image_build_context, "../../..");
  assert.equal(container.max_instances, 1);

  const binding = exactlyOne(config.durable_objects?.bindings, "durable object binding");
  assert.equal(binding.name, "AGENT_AWESOME_CONTAINER");
  assert.equal(binding.class_name, "AgentAwesomeContainer");
  assert.ok(
    config.migrations?.some((migration) =>
      migration.new_sqlite_classes?.includes("AgentAwesomeContainer"),
    ),
    "AgentAwesomeContainer migration must be declared",
  );

  const r2 = exactlyOne(config.r2_buckets, "R2 bucket binding");
  assert.equal(r2.binding, "CONTEXT_SNAPSHOTS");
  assert.equal(r2.bucket_name, "agent-awesome-beta-context");
  assert.equal(config.vars?.AGENTAWESOME_MODEL_PROVIDER_ID, "openai");
  assert.equal(config.vars?.AGENTAWESOME_MODEL_ID, "gpt-mini");
  for (const secret of [
    "AGENTAWESOME_GATEWAY_TOKEN",
    "AGENTAWESOME_PERSISTENCE_TOKEN",
    "SLACK_SIGNING_SECRET",
    "SLACK_BOT_TOKEN",
    "OPENAI_API_KEY",
  ]) {
    assert.ok(config.secrets?.required?.includes(secret), `${secret} must be required`);
  }
}

/** assertContainerEnvironment proves critical Worker vars reach the container. */
function assertContainerEnvironment(app) {
  const mapped = app.buildContainerEnv(createEnv());
  assert.equal(mapped.AGENTAWESOME_GATEWAY_TOKEN, "gateway-token");
  assert.equal(mapped.AGENTAWESOME_PERSISTENCE_TOKEN, "persistence-token");
  assert.equal(mapped.AGENTAWESOME_MODEL_PROVIDER_ID, "openai");
  assert.equal(mapped.AGENTAWESOME_MODEL_ID, "gpt-mini");
  assert.equal(mapped.SLACK_SIGNING_SECRET, "slack-secret");
  assert.equal(mapped.SLACK_ENABLED, "true");
  assert.equal(mapped.SLACK_SOCKET_MODE, "false");
  assert.equal(mapped.SLACK_ALLOWED_TEAM_ID, "T1");
  assert.equal(mapped.SLACK_ALLOWED_USER_ID, "U1");
  assert.equal(mapped.SLACK_ALLOWED_CHANNEL_ID, "C1");
}

/** assertHealthzWorks proves unauthenticated liveness reaches the gateway only. */
async function assertHealthzWorks(app) {
  const recorder = createGatewayRecorder();
  const response = await app.routeRequest(
    new Request("https://agent-awesome.com/healthz"),
    createEnv(),
    recorder.dependencies,
  );
  assert.equal(response.status, 200);
  assert.equal(recorder.calls.length, 1);
  assert.equal(recorder.calls[0].pathname, "/healthz");
}

/** assertMCPAuthBoundary proves /mcp is hidden unless the gateway token matches. */
async function assertMCPAuthBoundary(app) {
  const unauthenticated = createGatewayRecorder();
  const denied = await app.routeRequest(
    new Request("https://agent-awesome.com/mcp", { method: "POST", body: "{}" }),
    createEnv(),
    unauthenticated.dependencies,
  );
  assert.equal(denied.status, 404);
  assert.equal(unauthenticated.calls.length, 0);

  const missingToken = createGatewayRecorder();
  const missingTokenDenied = await app.routeRequest(
    new Request("https://agent-awesome.com/mcp", {
      headers: { authorization: "Bearer gateway-token" },
      method: "POST",
      body: "{}",
    }),
    createEnv({ AGENTAWESOME_GATEWAY_TOKEN: "" }),
    missingToken.dependencies,
  );
  assert.equal(missingTokenDenied.status, 404);
  assert.equal(missingToken.calls.length, 0);

  const authenticated = createGatewayRecorder();
  const allowed = await app.routeRequest(
    new Request("https://agent-awesome.com/mcp", {
      headers: { authorization: "Bearer gateway-token" },
      method: "POST",
      body: "{}",
    }),
    createEnv(),
    authenticated.dependencies,
  );
  assert.equal(allowed.status, 200);
  assert.equal(authenticated.calls.length, 1);
  assert.equal(authenticated.calls[0].pathname, "/mcp");
}

/** assertSnapshotHeadMetadata proves snapshot freshness is visible without archive download. */
async function assertSnapshotHeadMetadata(app) {
  const recorder = createGatewayRecorder();
  const response = await app.routeRequest(
    new Request("https://agent-awesome.com/internal/context-snapshot", {
      headers: { authorization: "Bearer persistence-token" },
      method: "HEAD",
    }),
    createEnv({
      CONTEXT_SNAPSHOTS: {
        async get() {
          return null;
        },
        async head() {
          return {
            etag: "snapshot-etag",
            httpMetadata: { contentType: "application/gzip" },
            size: 128,
            uploaded: new Date("2026-05-10T12:00:00Z"),
          };
        },
        async put() {},
      },
    }),
    recorder.dependencies,
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("etag"), "snapshot-etag");
  assert.equal(response.headers.get("last-modified"), "Sun, 10 May 2026 12:00:00 GMT");
  assert.equal(response.headers.get("content-length"), "128");
  assert.equal(recorder.calls.length, 0);
}

/** assertSlackIngressReachesGateway proves only signed Slack events are forwarded. */
async function assertSlackIngressReachesGateway(app) {
  const body = JSON.stringify({
    type: "url_verification",
    challenge: "challenge-token",
  });
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await slackSignature("slack-secret", timestamp, body);
  const recorder = createGatewayRecorder();
  const response = await withMutedWorkerLogs(() =>
    app.routeRequest(
      new Request("https://agent-awesome.com/slack/events", {
        body,
        headers: {
          "content-type": "application/json",
          "x-slack-request-timestamp": timestamp,
          "x-slack-signature": signature,
        },
        method: "POST",
      }),
      createEnv(),
      recorder.dependencies,
    ),
  );
  assert.equal(response.status, 200);
  assert.equal(recorder.calls.length, 1);
  assert.equal(recorder.calls[0].pathname, "/slack/events");
  assert.equal(recorder.calls[0].body, body);

  const rejected = createGatewayRecorder();
  const rejectedResponse = await withMutedWorkerLogs(() =>
    app.routeRequest(
      new Request("https://agent-awesome.com/slack/events", {
        body,
        headers: {
          "x-slack-request-timestamp": timestamp,
          "x-slack-signature": "v0=bad",
        },
        method: "POST",
      }),
      createEnv(),
      rejected.dependencies,
    ),
  );
  assert.equal(rejectedResponse.status, 404);
  assert.equal(rejected.calls.length, 0);
}

/** withMutedWorkerLogs suppresses expected Worker logs during route assertions. */
async function withMutedWorkerLogs(fn) {
  const originalLog = console.log;
  const originalWarn = console.warn;
  console.log = () => {};
  console.warn = () => {};
  try {
    return await fn();
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
}

/** createGatewayRecorder captures requests that would be sent to the container. */
function createGatewayRecorder() {
  const calls = [];
  return {
    calls,
    dependencies: {
      async fetchGateway(request) {
        const clone = request.clone();
        calls.push({
          body: await clone.text(),
          method: request.method,
          pathname: new URL(request.url).pathname,
        });
        return new Response("gateway ok\n", { status: 200 });
      },
    },
  };
}

/** createEnv returns the minimum Worker environment needed by smoke checks. */
function createEnv(overrides = {}) {
  return {
    AGENTAWESOME_GATEWAY_TOKEN: "gateway-token",
    AGENTAWESOME_PERSISTENCE_TOKEN: "persistence-token",
    SLACK_SIGNING_SECRET: "slack-secret",
    SLACK_ALLOWED_TEAM_ID: "T1",
    SLACK_ALLOWED_USER_ID: "U1",
    SLACK_ALLOWED_CHANNEL_ID: "C1",
    CONTEXT_SNAPSHOTS: {
      async get() {
        return null;
      },
      async head() {
        return null;
      },
      async put() {},
    },
    ...overrides,
  };
}

/** slackSignature computes the HMAC signature Slack sends for one body. */
async function slackSignature(secret, timestamp, body) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`v0:${timestamp}:${body}`),
  );
  return `v0=${hexEncode(new Uint8Array(digest))}`;
}

/** hexEncode renders bytes as lowercase hexadecimal text. */
function hexEncode(bytes) {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** exactlyOne returns the only element in a required configuration list. */
function exactlyOne(values, name) {
  assert.ok(Array.isArray(values), `${name} must be an array`);
  assert.equal(values.length, 1, `${name} must have exactly one item`);
  return values[0];
}

await main();
