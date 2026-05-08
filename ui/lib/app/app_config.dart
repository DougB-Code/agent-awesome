/// Defines runtime configuration for local Agent Awesome services.
library;

import 'dart:io';

/// AppConfig stores endpoint and identity settings for service clients.
class AppConfig {
  /// Creates an immutable app configuration.
  const AppConfig({
    required this.agentApiBaseUrl,
    required this.agentGatewayBaseUrl,
    required this.agentContextApiBaseUrl,
    required this.memoryMcpUrl,
    required this.agentAppName,
    required this.agentUserId,
    required this.workspaceRoot,
    required this.autoStartLocalServices,
    required this.runtimeProfilePath,
    this.litertLmExecutable = 'litert-lm',
    this.localModelBaseUrl = 'http://127.0.0.1:11666',
    this.gatewayAuthorizationHeader = '',
  });

  /// Builds configuration from Flutter compile-time environment values.
  factory AppConfig.fromEnvironment() {
    return AppConfig(
      agentApiBaseUrl: const String.fromEnvironment(
        'AGENT_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080/api',
      ),
      agentGatewayBaseUrl: const String.fromEnvironment(
        'AGENT_GATEWAY_BASE_URL',
        defaultValue: 'http://127.0.0.1:8070/api',
      ),
      agentContextApiBaseUrl: const String.fromEnvironment(
        'AGENT_CONTEXT_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8081/api/context',
      ),
      memoryMcpUrl: const String.fromEnvironment(
        'MEMORY_MCP_URL',
        defaultValue: 'http://127.0.0.1:8090/mcp',
      ),
      agentAppName: const String.fromEnvironment(
        'AGENT_APP_NAME',
        defaultValue: 'personal_pilot',
      ),
      agentUserId: const String.fromEnvironment(
        'AGENT_USER_ID',
        defaultValue: 'doug',
      ),
      workspaceRoot: const String.fromEnvironment(
        'AGENTAWESOME_WORKSPACE_ROOT',
        defaultValue: '/home/doug/dev/agentawesome/agent',
      ),
      autoStartLocalServices: const bool.fromEnvironment(
        'AUTO_START_LOCAL_SERVICES',
        defaultValue: true,
      ),
      runtimeProfilePath: const String.fromEnvironment(
        'AGENTAWESOME_RUNTIME_PROFILE',
        defaultValue: '',
      ),
      litertLmExecutable: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LITERT_LM',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LITERT_LM',
        fallback: 'litert-lm',
      ),
      localModelBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LOCAL_MODEL_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LOCAL_MODEL_BASE_URL',
        fallback: 'http://127.0.0.1:11666',
      ),
      gatewayAuthorizationHeader: _gatewayAuthorizationHeaderFromEnvironment(),
    );
  }

  /// Base URL for the ADK REST API.
  final String agentApiBaseUrl;

  /// Base URL for the Agent Awesome gateway API.
  final String agentGatewayBaseUrl;

  /// Base URL for the harness-owned context API.
  final String agentContextApiBaseUrl;

  /// Memory MCP URL exposed by the Agent Awesome gateway control plane.
  String get agentGatewayMcpUrl {
    final uri = Uri.parse(agentGatewayBaseUrl);
    return uri.replace(path: '/mcp', query: null).toString();
  }

  /// Context API URL exposed through the Agent Awesome gateway.
  String get agentGatewayContextBaseUrl {
    final uri = Uri.parse(agentGatewayBaseUrl);
    return uri.replace(path: '/api/context', query: null).toString();
  }

  /// Direct memory MCP JSON-RPC endpoint used as the gateway upstream.
  final String memoryMcpUrl;

  /// ADK app name that hosts the configured agent.
  final String agentAppName;

  /// ADK user id used for local sessions.
  final String agentUserId;

  /// Root directory containing the ui, memory, harness, and gateway packages.
  final String workspaceRoot;

  /// Whether the UI should manage local services during initialization.
  final bool autoStartLocalServices;

  /// Optional JSON runtime profile path for harness and MCP topology.
  final String runtimeProfilePath;

  /// LiteRT-LM executable path used by the local model runtime.
  final String litertLmExecutable;

  /// Loopback base URL exposed by the local model runtime.
  final String localModelBaseUrl;

  /// OpenAI-compatible chat completions URL exposed by the local runtime.
  String get localModelChatCompletionsUrl {
    final uri = Uri.parse(localModelBaseUrl);
    return uri.replace(path: '/v1/chat/completions', query: null).toString();
  }

  /// Health URL exposed by the local model runtime.
  String get localModelHealthUrl {
    final uri = Uri.parse(localModelBaseUrl);
    return uri.replace(path: '/health', query: null).toString();
  }

  /// Full Authorization header sent to protected gateway endpoints.
  final String gatewayAuthorizationHeader;

  /// Headers required when the UI calls protected gateway routes.
  Map<String, String> get gatewayAuthHeaders {
    final header = gatewayAuthorizationHeader.trim();
    if (header.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{'Authorization': header};
  }

  /// Bearer token value extracted from the configured gateway auth header.
  String get gatewayBearerToken {
    final header = gatewayAuthorizationHeader.trim();
    const prefix = 'Bearer ';
    if (!header.toLowerCase().startsWith(prefix.toLowerCase())) {
      return '';
    }
    return header.substring(prefix.length).trim();
  }

  /// Directory where managed service logs are written.
  String get serviceLogDirectory {
    return '$workspaceRoot/logs';
  }
}

/// Reads one value from compile-time config, runtime env, or a fallback.
String _environmentValue({
  required String compiled,
  required String runtimeName,
  required String fallback,
}) {
  final fromCompile = compiled.trim();
  if (fromCompile.isNotEmpty) {
    return fromCompile;
  }
  final fromRuntime = Platform.environment[runtimeName]?.trim() ?? '';
  if (fromRuntime.isNotEmpty) {
    return fromRuntime;
  }
  return fallback;
}

/// Reads gateway auth from compile-time or desktop runtime environment values.
String _gatewayAuthorizationHeaderFromEnvironment() {
  const compiledHeader = String.fromEnvironment(
    'AGENTAWESOME_GATEWAY_AUTHORIZATION',
    defaultValue: '',
  );
  final configuredHeader = compiledHeader.trim().isNotEmpty
      ? compiledHeader
      : Platform.environment['AGENTAWESOME_GATEWAY_AUTHORIZATION'] ?? '';
  if (configuredHeader.trim().isNotEmpty) {
    return configuredHeader.trim();
  }
  const compiledToken = String.fromEnvironment(
    'AGENTAWESOME_GATEWAY_TOKEN',
    defaultValue: '',
  );
  final token = compiledToken.trim().isNotEmpty
      ? compiledToken
      : Platform.environment['AGENTAWESOME_GATEWAY_TOKEN'] ?? '';
  if (token.trim().isEmpty) {
    return '';
  }
  return 'Bearer ${token.trim()}';
}
