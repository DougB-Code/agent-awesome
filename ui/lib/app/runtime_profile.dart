/// Loads runtime profile files and resolves app-owned profile paths.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/runtime_profile.dart';
import 'app_config.dart';

export '../domain/runtime_profile.dart';

/// HarnessRuntimeLaunch derives app launch details from harness profile data.
extension HarnessRuntimeLaunch on HarnessRuntime {
  /// URL used to prove harness readiness.
  String get sessionsUrl {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/apps/$appName/users/$userId/sessions';
  }

  /// Command arguments passed to the built harness executable.
  List<String> get arguments {
    return <String>[
      'run',
      '--model',
      modelConfigPath,
      '--agent',
      agentConfigPath,
      '--tool',
      toolConfigPath,
      if (contextApiBaseUrl.isNotEmpty) ...<String>[
        '--context-api-addr',
        _listenAddress(contextApiBaseUrl, _contextPort(contextApiBaseUrl)),
      ],
      '--',
      'web',
      '--port',
      port.toString(),
      'api',
      '--webui_address',
      webUiAddress,
    ];
  }

  /// Host and optional port passed to ADK for local REST API CORS headers.
  String get webUiAddress {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'localhost:$port';
    }
    if (uri.hasPort) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  }
}

/// GatewayRuntimeLaunch derives app launch details from gateway profile data.
extension GatewayRuntimeLaunch on GatewayRuntime {
  /// Memory MCP URL exposed by this gateway control plane.
  String get mcpUrl {
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(path: '/mcp', query: null).toString();
  }

  /// Effective beta status URL for this gateway.
  String get effectiveStatusUrl {
    if (statusUrl.trim().isNotEmpty) {
      return statusUrl;
    }
    final uri = Uri.parse(apiBaseUrl);
    return uri
        .replace(path: '/api/gateway/beta-status', query: null)
        .toString();
  }

  /// Command arguments passed to the built gateway executable without profile grants.
  List<String> get arguments {
    return _gatewayBaseArguments(this);
  }
}

/// Builds gateway launch arguments for the complete active runtime profile.
List<String> gatewayArgumentsForProfile(RuntimeProfile profile) {
  return <String>[
    ..._gatewayBaseArguments(profile.gateway),
    '--memory-domains-json',
    jsonEncode(_gatewayMemoryDomainJson(profile.memoryServers)),
    '--memory-policy-json',
    jsonEncode(profile.agentMemory.toJson()),
    '--memory-services-json',
    jsonEncode(_gatewayMemoryServiceJson(profile.memoryServers)),
  ];
}

/// Encodes enabled memory domains in the gateway config shape.
List<Map<String, dynamic>> _gatewayMemoryDomainJson(
  List<McpServerRuntime> servers,
) {
  return servers
      .map(
        (server) => <String, dynamic>{
          'id': server.id,
          'label': server.label,
          'endpoint': server.endpoint,
          if (server.healthUrl.trim().isNotEmpty)
            'health_url': server.healthUrl,
        },
      )
      .toList();
}

/// Encodes UI-managed memory service health checks for gateway readiness.
List<Map<String, dynamic>> _gatewayMemoryServiceJson(
  List<McpServerRuntime> servers,
) {
  return servers
      .map(
        (server) => <String, dynamic>{
          'domain_id': server.id,
          'name': server.id == 'memory' ? 'memory' : 'memory-${server.id}',
          if (server.healthUrl.trim().isNotEmpty)
            'health_url': server.healthUrl,
          'auto_start': false,
        },
      )
      .toList();
}

/// Builds gateway arguments that do not depend on agent-profile grants.
List<String> _gatewayBaseArguments(GatewayRuntime gateway) {
  return <String>[
    '--addr',
    _listenAddress(gateway.apiBaseUrl, gateway.port),
    '--harness-base-url',
    gateway.harnessBaseUrl,
    '--context-base-url',
    gateway.contextBaseUrl,
    '--memory-mcp-url',
    gateway.memoryMcpUrl,
    '--app-name',
    gateway.appName,
    '--user-id',
    gateway.userId,
    if (gateway.modelProviderId.trim().isNotEmpty) ...<String>[
      '--model-provider-id',
      gateway.modelProviderId,
    ],
    if (gateway.modelId.trim().isNotEmpty) ...<String>[
      '--model-id',
      gateway.modelId,
    ],
  ];
}

/// Encodes a runtime profile as stable, human-editable JSON.
String encodeRuntimeProfileJson(RuntimeProfile profile) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(profile.toJson())}\n';
}

/// Encodes an MCP server runtime config as stable, human-editable JSON.
String encodeMcpServerRuntimeJson(McpServerRuntime server) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(server.toJson())}\n';
}

/// RuntimeProfileLoader loads and validates the configured or shipped profile.
class RuntimeProfileLoader {
  /// Creates a runtime profile loader.
  const RuntimeProfileLoader(this.config);

  /// App configuration containing the optional profile path.
  final AppConfig config;

  /// Loads the profile file selected by AppConfig.
  Future<RuntimeProfile> load() async {
    final file = await resolveProfileFile();
    return loadFile(file);
  }

  /// Loads one profile file and expands supported environment templates.
  Future<RuntimeProfile> loadFile(File file) async {
    final decoded = jsonDecode(_expandTemplate(await file.readAsString()));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Runtime profile must be a JSON object');
    }
    return RuntimeProfile.fromJson(decoded);
  }

  /// Resolves and creates the selected profile file when using defaults.
  Future<File> resolveProfileFile() async {
    final configured = config.runtimeProfilePath.trim();
    if (configured.isNotEmpty) {
      return File(configured);
    }
    final file = File(defaultRuntimeProfilePath());
    if (await file.exists()) {
      return file;
    }
    final template = File(shippedRuntimeProfilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(await template.readAsString());
    return file;
  }

  /// Returns the default profile path in the operating system config folder.
  String defaultRuntimeProfilePath() {
    return '${runtimeProfilesDirectoryPath()}/agent_awesome.json';
  }

  /// Returns the shipped profile template path in the workspace.
  String shippedRuntimeProfilePath() {
    return '${config.workspaceRoot}/ui/runtime_profiles/agent_awesome.json';
  }

  /// Expands supported template variables in profile JSON content.
  String _expandTemplate(String profile) {
    var expanded = profile;
    for (final entry in _templateVariables().entries) {
      expanded = expanded.replaceAll('\${${entry.key}}', entry.value);
    }
    return expanded;
  }

  /// Returns template variables available to shipped runtime profiles.
  Map<String, String> _templateVariables() {
    final agentApi = Uri.parse(config.agentApiBaseUrl);
    final memoryMcp = Uri.parse(config.memoryMcpUrl);
    final gatewayApi = Uri.parse(config.agentGatewayBaseUrl);
    final contextApi = Uri.parse(config.agentContextApiBaseUrl);
    return <String, String>{
      'AGENTAWESOME_WORKSPACE_ROOT': config.workspaceRoot,
      'AGENTAWESOME_CONFIG_DIR': agentAwesomeConfigDirectoryPath(),
      'AGENTAWESOME_DATA_DIR': agentAwesomeDataDirectoryPath(),
      'AGENT_API_BASE_URL': config.agentApiBaseUrl,
      'AGENT_API_PORT': _portString(agentApi, 8080),
      'AGENT_CONTEXT_API_BASE_URL': config.agentContextApiBaseUrl,
      'AGENT_CONTEXT_API_PORT': _portString(contextApi, 8081),
      'AGENT_GATEWAY_BASE_URL': config.agentGatewayBaseUrl,
      'AGENT_GATEWAY_CONTEXT_BASE_URL': config.agentGatewayContextBaseUrl,
      'AGENT_GATEWAY_MCP_URL': config.agentGatewayMcpUrl,
      'AGENT_GATEWAY_PORT': _portString(gatewayApi, 8070),
      'AGENT_GATEWAY_HEALTH_URL': _healthUrl(config.agentGatewayBaseUrl),
      'AGENT_GATEWAY_STATUS_URL': _betaStatusUrl(config.agentGatewayBaseUrl),
      'AGENT_APP_NAME': config.agentAppName,
      'AGENT_USER_ID': config.agentUserId,
      'MEMORY_MCP_URL': config.memoryMcpUrl,
      'MEMORY_MCP_ADDR': memoryMcp.authority,
      'MEMORY_DB_PATH': defaultMemoryDatabasePath(),
      'MEMORY_DATA_DIR': defaultMemoryDataDirectoryPath(),
      'MEMORY_FIREWALL_POLICY_PATH': memoryFirewallPolicyPath(),
      'MEMORY_HEALTH_URL': _healthUrl(config.memoryMcpUrl),
      'AUTO_START_LOCAL_SERVICES': config.autoStartLocalServices.toString(),
    };
  }
}

/// Returns the Agent Awesome app config directory for this operating system.
String agentAwesomeAppConfigDirectoryPath() {
  final override = Platform.environment['AGENTAWESOME_CONFIG_HOME']?.trim();
  if (override != null && override.isNotEmpty) {
    return override;
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\agent-awesome';
    }
  }
  final home = Platform.environment['HOME']?.trim();
  if (Platform.isMacOS && home != null && home.isNotEmpty) {
    return '$home/Library/Application Support/agent-awesome';
  }
  final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME']?.trim();
  if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
    return '$xdgConfigHome/agent-awesome';
  }
  if (home != null && home.isNotEmpty) {
    return '$home/.config/agent-awesome';
  }
  return '.agent-awesome';
}

/// Returns the directory where editable Agent Awesome configuration files live.
String agentAwesomeConfigDirectoryPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/config';
}

/// Returns the directory where Agent Awesome-owned data files live.
String agentAwesomeDataDirectoryPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/data';
}

/// Returns the directory where editable runtime profiles live.
String runtimeProfilesDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/profiles';
}

/// Returns the directory where editable model config files live.
String modelConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/models';
}

/// Returns the shared model config referenced by runtime profiles.
String defaultModelConfigPath() {
  return '${modelConfigsDirectoryPath()}/model.yaml';
}

/// Returns the directory where editable agent config files live.
String agentConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/agents';
}

/// Returns the directory where editable tool config files live.
String toolConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/tools';
}

/// Returns the directory where editable memory domain metadata lives.
String memoryDomainConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/memory-domains';
}

/// Returns the default SQLite database path for local memory.
String defaultMemoryDatabasePath() {
  return '${agentAwesomeDataDirectoryPath()}/memory/memory.db';
}

/// Returns the default sidecar data directory for local memory.
String defaultMemoryDataDirectoryPath() {
  return '${agentAwesomeDataDirectoryPath()}/memory/files';
}

/// Returns the SQLite database path for one local memory domain.
String memoryDomainDatabasePath(String domainId) {
  return '${agentAwesomeDataDirectoryPath()}/memory/$domainId/memory.db';
}

/// Returns the sidecar data directory for one local memory domain.
String memoryDomainDataDirectoryPath(String domainId) {
  return '${agentAwesomeDataDirectoryPath()}/memory/$domainId/files';
}

/// Returns the app-owned memory firewall policy path consumed by memoryd.
String memoryFirewallPolicyPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/memory_firewall_policy.json';
}

/// Returns the health-check URL for a base service endpoint.
String _healthUrl(String endpoint) {
  final uri = Uri.parse(endpoint);
  return uri.replace(path: '/healthz', query: '').toString();
}

/// Returns the beta status URL for a gateway base endpoint.
String _betaStatusUrl(String endpoint) {
  final uri = Uri.parse(endpoint);
  return uri.replace(path: '/api/gateway/beta-status', query: null).toString();
}

/// Returns a URI port or a default when the URI omits one.
String _portString(Uri uri, int fallback) {
  if (uri.hasPort) {
    return uri.port.toString();
  }
  return fallback.toString();
}

/// Returns the listen port encoded in a context API URL.
int _contextPort(String contextApiBaseUrl) {
  final uri = Uri.parse(contextApiBaseUrl);
  if (uri.hasPort) {
    return uri.port;
  }
  return 8081;
}

/// Returns the host:port listen address for a base API URL.
String _listenAddress(String apiBaseUrl, int fallbackPort) {
  final uri = Uri.parse(apiBaseUrl);
  final port = uri.hasPort ? uri.port : fallbackPort;
  final host = uri.host.isEmpty ? '127.0.0.1' : uri.host;
  return '$host:$port';
}
