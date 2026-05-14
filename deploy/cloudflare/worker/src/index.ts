// This Worker binds Cloudflare Containers to the testable Agent Awesome router.
import { Container, getContainer } from "@cloudflare/containers";
import { env as workerEnv } from "cloudflare:workers";

import {
  buildContainerEnv,
  containerName,
  containerPortReadyTimeoutMS,
  gatewayPort,
  routeRequest,
  type Env as AppEnv,
} from "./app";

/** Env describes Worker bindings, vars, and secrets used by the pilot. */
export interface Env extends AppEnv {
  AGENT_AWESOME_CONTAINER: DurableObjectNamespace<AgentAwesomeContainer>;
}

/** AgentAwesomeContainer configures the Linux container that runs the Go services. */
export class AgentAwesomeContainer extends Container {
  defaultPort = gatewayPort;
  requiredPorts = [gatewayPort];
  sleepAfter = "30m";
  envVars = buildContainerEnv(workerEnv as AppEnv);

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

/** fetchPilotContainer waits for the gateway port with pilot-friendly startup time. */
async function fetchPilotContainer(
  request: Request,
  env: Env,
): Promise<Response> {
  const container = getContainer(env.AGENT_AWESOME_CONTAINER, containerName);
  await container.startAndWaitForPorts({
    ports: [gatewayPort],
    cancellationOptions: {
      portReadyTimeoutMS: containerPortReadyTimeoutMS,
      waitInterval: 500,
    },
  });
  return container.fetch(request);
}

export default {
  /** fetch handles Worker HTTP requests and delegates service routes to the container. */
  fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    return routeRequest(request, env, {
      fetchGateway: fetchPilotContainer,
      waitUntil: context.waitUntil.bind(context),
    });
  },
} satisfies ExportedHandler<Env>;
