/// Defines runtime configuration for local Agent Awesome services.
library;

/// AppConfig stores endpoint and identity settings for service clients.
class AppConfig {
  /// Creates an immutable app configuration.
  const AppConfig({
    required this.agentApiBaseUrl,
    required this.agentGatewayBaseUrl,
    required this.memoryMcpUrl,
    required this.agentAppName,
    required this.agentUserId,
    required this.workspaceRoot,
    required this.autoStartLocalServices,
    required this.runtimeProfilePath,
  });

  /// Builds configuration from Flutter compile-time environment values.
  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      agentApiBaseUrl: String.fromEnvironment(
        'AGENT_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080/api',
      ),
      agentGatewayBaseUrl: String.fromEnvironment(
        'AGENT_GATEWAY_BASE_URL',
        defaultValue: 'http://127.0.0.1:8070/api',
      ),
      memoryMcpUrl: String.fromEnvironment(
        'MEMORY_MCP_URL',
        defaultValue: 'http://127.0.0.1:8090/mcp',
      ),
      agentAppName: String.fromEnvironment(
        'AGENT_APP_NAME',
        defaultValue: 'personal_pilot',
      ),
      agentUserId: String.fromEnvironment(
        'AGENT_USER_ID',
        defaultValue: 'doug',
      ),
      workspaceRoot: String.fromEnvironment(
        'AGENTAWESOME_WORKSPACE_ROOT',
        defaultValue: '/home/doug/dev/agentawesome/agent',
      ),
      autoStartLocalServices: bool.fromEnvironment(
        'AUTO_START_LOCAL_SERVICES',
        defaultValue: true,
      ),
      runtimeProfilePath: String.fromEnvironment(
        'AGENTAWESOME_RUNTIME_PROFILE',
        defaultValue: '',
      ),
    );
  }

  /// Base URL for the ADK REST API.
  final String agentApiBaseUrl;

  /// Base URL for the Agent Awesome gateway API.
  final String agentGatewayBaseUrl;

  /// URL for the memory MCP JSON-RPC endpoint.
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

  /// Directory where managed service logs are written.
  String get serviceLogDirectory {
    return '$workspaceRoot/logs';
  }
}
