/// Loads runtime profile files and resolves app-owned profile paths.
library;

import 'dart:convert';
import 'dart:io';

import '../domain/runtime_profile.dart';
import 'app_config.dart';

export '../domain/runtime_profile.dart';

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
    final profile = RuntimeProfile.fromJson(decoded);
    final mcpServers = <McpServerRuntime>[
      await _loadMcpServerConfig(profile.memoryServerConfigPath, 'memory'),
    ];
    return profile.copyWith(
      mcpServers: _controlPlaneMcpServers(profile, mcpServers),
    );
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
    return '${runtimeProfilesDirectoryPath()}/personal_assistant.json';
  }

  /// Returns the shipped profile template path in the workspace.
  String shippedRuntimeProfilePath() {
    return '${config.workspaceRoot}/ui/runtime_profiles/personal_assistant.json';
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
      'MEMORY_HEALTH_URL': _healthUrl(config.memoryMcpUrl),
      'AUTO_START_LOCAL_SERVICES': config.autoStartLocalServices.toString(),
    };
  }

  /// Loads one required app-owned MCP service config referenced by a profile.
  Future<McpServerRuntime> _loadMcpServerConfig(
    String path,
    String expectedKind,
  ) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException(
        '$expectedKind server config does not exist',
        path,
      );
    }
    final decoded = jsonDecode(_expandTemplate(await file.readAsString()));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        '$expectedKind server config "$path" must be a JSON object',
      );
    }
    final server = McpServerRuntime.fromJson(decoded);
    if (server.kind != expectedKind) {
      throw FormatException(
        '$expectedKind server config "$path" must have kind "$expectedKind"',
      );
    }
    return server;
  }

  /// Rewrites UI MCP endpoints to the gateway when a control plane is active.
  List<McpServerRuntime> _controlPlaneMcpServers(
    RuntimeProfile profile,
    List<McpServerRuntime> servers,
  ) {
    final gateway = profile.gateway;
    if (gateway == null || !gateway.enabled) {
      return servers;
    }
    return servers.map((server) {
      if (server.kind != 'memory') {
        return server;
      }
      return server.copyWith(endpoint: gateway.mcpUrl);
    }).toList();
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

/// Returns the directory where editable memory server config files live.
String memoryServerConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/memory';
}

/// Returns the default SQLite database path for local memory.
String defaultMemoryDatabasePath() {
  return '${agentAwesomeDataDirectoryPath()}/memory/memory.db';
}

/// Returns the default sidecar data directory for local memory.
String defaultMemoryDataDirectoryPath() {
  return '${agentAwesomeDataDirectoryPath()}/memory/files';
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
