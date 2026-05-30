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
    this.sourceControlMcpUrl = 'http://127.0.0.1:8095/mcp',
    required this.agentAppName,
    required this.agentUserId,
    required this.workspaceRoot,
    required this.autoStartLocalServices,
    required this.runtimeProfilePath,
    this.litertLmExecutable = 'litert-lm',
    this.llamaCppExecutable = 'llama-server',
    this.localModelBaseUrl = 'http://127.0.0.1:11666',
    this.llamaCppBaseUrl = 'http://127.0.0.1:11667',
    this.gatewayAuthorizationHeader = '',
  });

  /// Builds configuration from Flutter compile-time environment values.
  factory AppConfig.fromEnvironment() {
    final workspaceRoot = _environmentValue(
      compiled: const String.fromEnvironment(
        'AGENTAWESOME_WORKSPACE_ROOT',
        defaultValue: '',
      ),
      runtimeName: 'AGENTAWESOME_WORKSPACE_ROOT',
      fallback: _defaultWorkspaceRoot(),
    );
    return AppConfig(
      agentApiBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENT_API_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENT_API_BASE_URL',
        fallback: 'http://127.0.0.1:8080/api',
      ),
      agentGatewayBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENT_GATEWAY_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENT_GATEWAY_BASE_URL',
        fallback: 'http://127.0.0.1:8070/api',
      ),
      agentContextApiBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENT_CONTEXT_API_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENT_CONTEXT_API_BASE_URL',
        fallback: 'http://127.0.0.1:8081/api/context',
      ),
      memoryMcpUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'MEMORY_MCP_URL',
          defaultValue: '',
        ),
        runtimeName: 'MEMORY_MCP_URL',
        fallback: 'http://127.0.0.1:8090/mcp',
      ),
      sourceControlMcpUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'SOURCECONTROL_MCP_URL',
          defaultValue: '',
        ),
        runtimeName: 'SOURCECONTROL_MCP_URL',
        fallback: 'http://127.0.0.1:8095/mcp',
      ),
      agentAppName: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENT_APP_NAME',
          defaultValue: '',
        ),
        runtimeName: 'AGENT_APP_NAME',
        fallback: 'agent_awesome',
      ),
      agentUserId: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENT_USER_ID',
          defaultValue: '',
        ),
        runtimeName: 'AGENT_USER_ID',
        fallback: _defaultAgentUserId(),
      ),
      workspaceRoot: workspaceRoot,
      autoStartLocalServices: _boolEnvironmentValue(
        compiled: const String.fromEnvironment(
          'AUTO_START_LOCAL_SERVICES',
          defaultValue: '',
        ),
        runtimeName: 'AUTO_START_LOCAL_SERVICES',
        fallback: true,
      ),
      runtimeProfilePath: '',
      litertLmExecutable: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LITERT_LM',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LITERT_LM',
        fallback: 'litert-lm',
      ),
      llamaCppExecutable: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LLAMA_CPP_SERVER',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LLAMA_CPP_SERVER',
        fallback: _defaultLlamaCppExecutable(workspaceRoot),
      ),
      localModelBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LOCAL_MODEL_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LOCAL_MODEL_BASE_URL',
        fallback: 'http://127.0.0.1:11666',
      ),
      llamaCppBaseUrl: _environmentValue(
        compiled: const String.fromEnvironment(
          'AGENTAWESOME_LLAMA_CPP_BASE_URL',
          defaultValue: '',
        ),
        runtimeName: 'AGENTAWESOME_LLAMA_CPP_BASE_URL',
        fallback: 'http://127.0.0.1:11667',
      ),
      gatewayAuthorizationHeader: _gatewayAuthorizationHeaderFromEnvironment(),
    );
  }

  /// Base URL for the assistant API.
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

  /// Direct source-control MCP JSON-RPC endpoint used by workflows.
  final String sourceControlMcpUrl;

  /// Assistant app name that hosts the configured agent.
  final String agentAppName;

  /// Assistant user id used for local sessions.
  final String agentUserId;

  /// Root directory containing app service packages or release bundle files.
  final String workspaceRoot;

  /// Whether the UI should manage local services during initialization.
  final bool autoStartLocalServices;

  /// Internal JSON runtime topology path used by tests and controlled bootstraps.
  final String runtimeProfilePath;

  /// LiteRT-LM executable path used by the local model runtime.
  final String litertLmExecutable;

  /// llama.cpp server executable path used by the local model runtime.
  final String llamaCppExecutable;

  /// Loopback base URL exposed by the LiteRT-LM local model runtime.
  final String localModelBaseUrl;

  /// Loopback base URL exposed by the llama.cpp local model runtime.
  final String llamaCppBaseUrl;

  /// OpenAI-compatible chat completions URL exposed by LiteRT-LM.
  String get localModelChatCompletionsUrl {
    final uri = Uri.parse(localModelBaseUrl);
    return uri.replace(path: '/v1/chat/completions', query: null).toString();
  }

  /// Health URL exposed by LiteRT-LM.
  String get localModelHealthUrl {
    final uri = Uri.parse(localModelBaseUrl);
    return uri.replace(path: '/health', query: null).toString();
  }

  /// OpenAI-compatible chat completions URL exposed by llama.cpp.
  String get llamaCppChatCompletionsUrl {
    final uri = Uri.parse(llamaCppBaseUrl);
    return uri.replace(path: '/v1/chat/completions', query: null).toString();
  }

  /// Health URL exposed by llama.cpp.
  String get llamaCppHealthUrl {
    final uri = Uri.parse(llamaCppBaseUrl);
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

/// Reads a boolean from compile-time config, runtime env, or a fallback.
bool _boolEnvironmentValue({
  required String compiled,
  required String runtimeName,
  required bool fallback,
}) {
  final value = _environmentValue(
    compiled: compiled,
    runtimeName: runtimeName,
    fallback: fallback.toString(),
  ).trim();
  if (value.isEmpty) {
    return fallback;
  }
  return value.toLowerCase() == 'true';
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

/// Returns a non-personal default user id for local runtime sessions.
String _defaultAgentUserId() {
  final username = Platform.environment['USER']?.trim().isNotEmpty == true
      ? Platform.environment['USER']!.trim()
      : Platform.environment['USERNAME']?.trim();
  if (username != null && username.isNotEmpty) {
    return username;
  }
  return 'local-user';
}

/// Finds the nearest Agent Awesome runtime root for app launches.
String _defaultWorkspaceRoot() {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    executableDirectory,
    executableDirectory.parent,
  ];
  for (final candidate in candidates) {
    if (_isAgentAwesomeWorkspace(candidate)) {
      return candidate.absolute.path;
    }
  }
  return Directory.current.absolute.path;
}

/// Reports whether a directory contains the shipped runtime topology and binaries.
bool _isAgentAwesomeWorkspace(Directory directory) {
  final hasRuntimeTopology = File(
    '${directory.path}/ui/runtime_topology/agent_awesome.json',
  ).existsSync();
  final hasServiceDirectories =
      Directory('${directory.path}/harness').existsSync() &&
      Directory('${directory.path}/gateway').existsSync() &&
      Directory('${directory.path}/memory').existsSync();
  final hasRuntimeBinaries =
      File('${directory.path}/harness/build/bin/agent-awesome').existsSync() &&
      File(
        '${directory.path}/harness/build/bin/workflow-service',
      ).existsSync() &&
      File('${directory.path}/gateway/build/agent-gateway').existsSync() &&
      File('${directory.path}/memory/build/bin/memoryd').existsSync();
  return hasRuntimeTopology && hasServiceDirectories && hasRuntimeBinaries;
}

/// Returns the bundled llama.cpp server path when present.
String _defaultLlamaCppExecutable(String workspaceRoot) {
  final workspace = Directory(workspaceRoot);
  final candidates = <String>[
    '${workspace.parent.path}/tools/ggml.ai/llama.cpp/llama-server',
    '${workspace.path}/tools/ggml.ai/llama.cpp/llama-server',
    'llama-server',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'llama-server';
}
