/// Defines runtime profiles that connect chat to harness and MCP services.
library;

import 'dart:convert';
import 'dart:io';

import 'app_config.dart';

/// RuntimeProfile describes the complete service topology for one UI session.
class RuntimeProfile {
  /// Creates an immutable runtime profile.
  const RuntimeProfile({
    required this.id,
    required this.label,
    required this.harness,
    required this.memoryServerConfigPath,
    required this.mcpServers,
  });

  /// Stable profile id.
  final String id;

  /// Human-readable profile label.
  final String label;

  /// Harness process and API configuration.
  final HarnessRuntime harness;

  /// Memory server config file referenced by this profile.
  final String memoryServerConfigPath;

  /// MCP servers available to the harness and UI.
  final List<McpServerRuntime> mcpServers;

  /// Returns enabled memory MCP servers.
  List<McpServerRuntime> get memoryServers {
    return mcpServers
        .where((server) => server.enabled && server.kind == 'memory')
        .toList();
  }

  /// Creates a runtime profile with selected fields replaced.
  RuntimeProfile copyWith({
    String? id,
    String? label,
    HarnessRuntime? harness,
    String? memoryServerConfigPath,
    List<McpServerRuntime>? mcpServers,
  }) {
    return RuntimeProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      harness: harness ?? this.harness,
      memoryServerConfigPath:
          memoryServerConfigPath ?? this.memoryServerConfigPath,
      mcpServers: mcpServers ?? this.mcpServers,
    );
  }

  /// Encodes this profile to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'harness': harness.toJson(),
      'memory_server_config': memoryServerConfigPath,
    };
  }

  /// Parses a runtime profile shell from decoded JSON.
  factory RuntimeProfile.fromJson(Map<String, dynamic> json) {
    return RuntimeProfile(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      harness: HarnessRuntime.fromJson(_requiredMap(json, 'harness')),
      memoryServerConfigPath: _requiredString(json, 'memory_server_config'),
      mcpServers: const <McpServerRuntime>[],
    );
  }
}

/// HarnessRuntime describes the ADK harness process and active config bundle.
class HarnessRuntime {
  /// Creates an immutable harness runtime definition.
  const HarnessRuntime({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.appName,
    required this.userId,
    required this.workingDirectory,
    required this.packagePath,
    required this.modelConfigPath,
    required this.agentConfigPath,
    required this.toolConfigPath,
    required this.port,
    required this.autoStart,
  });

  /// Stable harness id.
  final String id;

  /// Human-readable harness label.
  final String label;

  /// ADK API base URL.
  final String apiBaseUrl;

  /// ADK app name hosted by this harness.
  final String appName;

  /// ADK user id used for session APIs.
  final String userId;

  /// Directory where the Go package is built and run.
  final String workingDirectory;

  /// Go package path for the harness command.
  final String packagePath;

  /// Model config path passed to the harness.
  final String modelConfigPath;

  /// Agent config path passed to the harness.
  final String agentConfigPath;

  /// Tool config path passed to the harness.
  final String toolConfigPath;

  /// Web API listen port.
  final int port;

  /// Whether the UI should start this harness.
  final bool autoStart;

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

  /// Creates a harness runtime with selected fields replaced.
  HarnessRuntime copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    String? appName,
    String? userId,
    String? workingDirectory,
    String? packagePath,
    String? modelConfigPath,
    String? agentConfigPath,
    String? toolConfigPath,
    int? port,
    bool? autoStart,
  }) {
    return HarnessRuntime(
      id: id ?? this.id,
      label: label ?? this.label,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      appName: appName ?? this.appName,
      userId: userId ?? this.userId,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      packagePath: packagePath ?? this.packagePath,
      modelConfigPath: modelConfigPath ?? this.modelConfigPath,
      agentConfigPath: agentConfigPath ?? this.agentConfigPath,
      toolConfigPath: toolConfigPath ?? this.toolConfigPath,
      port: port ?? this.port,
      autoStart: autoStart ?? this.autoStart,
    );
  }

  /// Encodes this harness runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'api_base_url': apiBaseUrl,
      'app_name': appName,
      'user_id': userId,
      'working_directory': workingDirectory,
      'package_path': packagePath,
      'model_config': modelConfigPath,
      'agent_config': agentConfigPath,
      'tool_config': toolConfigPath,
      'port': port,
      'auto_start': autoStart,
    };
  }

  /// Parses harness runtime JSON from explicit profile values.
  factory HarnessRuntime.fromJson(Map<String, dynamic> json) {
    return HarnessRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      apiBaseUrl: _requiredString(json, 'api_base_url'),
      appName: _requiredString(json, 'app_name'),
      userId: _requiredString(json, 'user_id'),
      workingDirectory: _requiredString(json, 'working_directory'),
      packagePath: _requiredString(json, 'package_path'),
      modelConfigPath: _requiredString(json, 'model_config'),
      agentConfigPath: _requiredString(json, 'agent_config'),
      toolConfigPath: _requiredString(json, 'tool_config'),
      port: _requiredInt(json, 'port'),
      autoStart: _requiredBool(json, 'auto_start'),
    );
  }
}

/// McpServerRuntime describes one memory, task, or auxiliary MCP server.
class McpServerRuntime {
  /// Creates an immutable MCP server runtime definition.
  const McpServerRuntime({
    required this.id,
    required this.label,
    required this.kind,
    required this.endpoint,
    required this.healthUrl,
    required this.workingDirectory,
    required this.packagePath,
    required this.arguments,
    required this.autoStart,
    required this.enabled,
  });

  /// Stable MCP server id.
  final String id;

  /// Human-readable MCP server label.
  final String label;

  /// Logical server kind, such as memory or tasks.
  final String kind;

  /// Streamable HTTP MCP endpoint.
  final String endpoint;

  /// Health URL used before and after launching.
  final String healthUrl;

  /// Directory where the Go package is built and run.
  final String workingDirectory;

  /// Go package path for managed local servers.
  final String packagePath;

  /// Command arguments for managed local servers.
  final List<String> arguments;

  /// Whether the UI should start this server.
  final bool autoStart;

  /// Whether the UI should query this server.
  final bool enabled;

  /// Parses an MCP server runtime definition from explicit profile values.
  factory McpServerRuntime.fromJson(Map<String, dynamic> json) {
    final endpoint = _requiredString(json, 'endpoint');
    return McpServerRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      kind: _requiredString(json, 'kind'),
      endpoint: endpoint,
      healthUrl: _requiredString(json, 'health_url'),
      workingDirectory: _optionalString(json['working_directory']),
      packagePath: _optionalString(json['package_path']),
      arguments: _stringList(json['arguments']),
      autoStart: _requiredBool(json, 'auto_start'),
      enabled: _requiredBool(json, 'enabled'),
    );
  }

  /// Creates an MCP server runtime with selected fields replaced.
  McpServerRuntime copyWith({
    String? id,
    String? label,
    String? kind,
    String? endpoint,
    String? healthUrl,
    String? workingDirectory,
    String? packagePath,
    List<String>? arguments,
    bool? autoStart,
    bool? enabled,
  }) {
    return McpServerRuntime(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      endpoint: endpoint ?? this.endpoint,
      healthUrl: healthUrl ?? this.healthUrl,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      packagePath: packagePath ?? this.packagePath,
      arguments: arguments ?? this.arguments,
      autoStart: autoStart ?? this.autoStart,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Encodes this MCP runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'kind': kind,
      'endpoint': endpoint,
      'health_url': healthUrl,
      'working_directory': workingDirectory,
      'package_path': packagePath,
      'arguments': arguments,
      'auto_start': autoStart,
      'enabled': enabled,
    };
  }
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
    final profile = RuntimeProfile.fromJson(decoded);
    return profile.copyWith(
      mcpServers: <McpServerRuntime>[
        await _loadMcpServerConfig(profile.memoryServerConfigPath, 'memory'),
      ],
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

  String _expandTemplate(String profile) {
    var expanded = profile;
    for (final entry in _templateVariables().entries) {
      expanded = expanded.replaceAll('\${${entry.key}}', entry.value);
    }
    return expanded;
  }

  Map<String, String> _templateVariables() {
    final agentApi = Uri.parse(config.agentApiBaseUrl);
    final memoryMcp = Uri.parse(config.memoryMcpUrl);
    return <String, String>{
      'AGENTAWESOME_WORKSPACE_ROOT': config.workspaceRoot,
      'AGENT_API_BASE_URL': config.agentApiBaseUrl,
      'AGENT_API_PORT': _portString(agentApi, 8080),
      'AGENT_APP_NAME': config.agentAppName,
      'AGENT_USER_ID': config.agentUserId,
      'MEMORY_MCP_URL': config.memoryMcpUrl,
      'MEMORY_MCP_ADDR': memoryMcp.authority,
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
}

/// Returns the Aurora app config directory for this operating system.
String auroraAppConfigDirectoryPath() {
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

/// Returns the directory where editable Aurora configuration files live.
String auroraConfigDirectoryPath() {
  return '${auroraAppConfigDirectoryPath()}/config';
}

/// Returns the directory where editable runtime profiles live.
String runtimeProfilesDirectoryPath() {
  return '${auroraConfigDirectoryPath()}/profiles';
}

/// Returns the directory where editable model config files live.
String modelConfigsDirectoryPath() {
  return '${auroraConfigDirectoryPath()}/models';
}

/// Returns the directory where editable agent config files live.
String agentConfigsDirectoryPath() {
  return '${auroraConfigDirectoryPath()}/agents';
}

/// Returns the directory where editable tool config files live.
String toolConfigsDirectoryPath() {
  return '${auroraConfigDirectoryPath()}/tools';
}

/// Returns the directory where editable memory server config files live.
String memoryServerConfigsDirectoryPath() {
  return '${auroraConfigDirectoryPath()}/memory';
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

String _healthUrl(String endpoint) {
  final uri = Uri.parse(endpoint);
  return uri.replace(path: '/healthz', query: '').toString();
}

String _portString(Uri uri, int fallback) {
  if (uri.hasPort) {
    return uri.port.toString();
  }
  return fallback.toString();
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Runtime profile field "$field" must be an object');
}

String _requiredString(Map<String, dynamic> json, String field) {
  final text = _optionalString(json[field]);
  if (text.isEmpty) {
    throw FormatException('Runtime profile field "$field" is required');
  }
  return text;
}

String _optionalString(dynamic value) {
  if (value == null) {
    return '';
  }
  final text = value.toString();
  return text;
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is int) {
    return value;
  }
  final parsed = int.tryParse(_optionalString(value));
  if (parsed == null) {
    throw FormatException('Runtime profile field "$field" must be an integer');
  }
  return parsed;
}

bool _requiredBool(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is bool) {
    return value;
  }
  final text = _optionalString(value).toLowerCase();
  if (text == 'true') {
    return true;
  }
  if (text == 'false') {
    return false;
  }
  throw FormatException('Runtime profile field "$field" must be a boolean');
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map(_optionalString).where((item) => item.isNotEmpty).toList();
}
