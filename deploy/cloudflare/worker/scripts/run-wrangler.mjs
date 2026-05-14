// This file runs Wrangler with repository-local state directories.
import { accessSync, constants, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const workerRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(workerRoot, "../../..");
const buildRoot = resolve(repoRoot, "build");

/** main validates Node and delegates to the package-local Wrangler binary. */
function main() {
  assertSupportedNode();
  const env = buildEnvironment();
  const executable = resolve(
    workerRoot,
    "node_modules/.bin",
    process.platform === "win32" ? "wrangler.cmd" : "wrangler",
  );
  const result = spawnSync(executable, process.argv.slice(2), {
    cwd: workerRoot,
    env,
    stdio: "inherit",
  });
  process.exit(result.status ?? 1);
}

/** assertSupportedNode fails early before Wrangler emits its own runtime error. */
function assertSupportedNode() {
  const major = Number.parseInt(process.versions.node.split(".")[0] ?? "0", 10);
  if (major >= 22) {
    return;
  }
  console.error(
    `Wrangler requires Node.js >=22. Current Node.js is ${process.version}. ` +
      "Run `nvm use` from the repository root before deploying.",
  );
  process.exit(1);
}

/** buildEnvironment returns process env plus writable Wrangler and Docker state. */
function buildEnvironment() {
  const env = { ...process.env };
  const home = env.HOME ?? "";
  ensureWritableEnv(
    env,
    "XDG_CONFIG_HOME",
    resolve(home, ".config"),
    resolve(buildRoot, "cloudflare-worker", "xdg"),
  );
  ensureWritableEnv(
    env,
    "DOCKER_CONFIG",
    resolve(home, ".docker"),
    resolve(buildRoot, "docker-config"),
  );
  ensureWritableEnv(
    env,
    "BUILDX_CONFIG",
    resolve(env.DOCKER_CONFIG ?? resolve(home, ".docker"), "buildx"),
    resolve(buildRoot, "docker-buildx"),
  );
  return env;
}

/** ensureWritableEnv keeps a default tool path unless it is not writable. */
function ensureWritableEnv(env, key, defaultDir, fallbackDir) {
  if (env[key] !== undefined && env[key] !== "") {
    mkdirSync(env[key], { recursive: true });
    return;
  }
  if (isWritableDirectory(defaultDir)) {
    return;
  }
  mkdirSync(fallbackDir, { recursive: true });
  env[key] = fallbackDir;
}

/** isWritableDirectory reports whether a command can create state in a directory. */
function isWritableDirectory(path) {
  if (path === "" || path === ".") {
    return false;
  }
  try {
    mkdirSync(path, { recursive: true });
    accessSync(path, constants.W_OK);
    const probe = resolve(path, `.agentawesome-write-test-${process.pid}`);
    writeFileSync(probe, "");
    rmSync(probe, { force: true });
    return true;
  } catch {
    return false;
  }
}

main();
