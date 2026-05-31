/// Loads agent runtime topology files and resolves app-owned topology paths.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/config_files.dart';
import '../domain/runtime_profile.dart';
import 'app_config.dart';

export '../domain/runtime_profile.dart';

/// HarnessRuntimeLaunch derives app launch details from harness topology data.
extension HarnessRuntimeLaunch on HarnessRuntime {
  /// URL used to prove harness readiness.
  String get sessionsUrl {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/apps/$appName/users/$userId/sessions';
  }

  /// Command arguments passed to the harness executable.
  List<String> get arguments {
    return _harnessBaseArguments(this);
  }

  /// Host and optional port passed to the assistant API for CORS headers.
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

/// Builds harness launch arguments for the complete active agent runtime topology.
List<String> harnessArgumentsForProfile(RuntimeProfile profile) {
  final arguments = _harnessBaseArguments(profile.harness);
  if (!profile.runbook.enabled || !profile.runbook.hostedByHarness) {
    return arguments;
  }
  return _insertBeforeRuntimeArgs(arguments, <String>[
    '--runbook-api-addr',
    _listenAddress(profile.runbook.apiBaseUrl, profile.runbook.port),
    '--runbook-definitions',
    runbookDefinitionsDirectoryPathForProfile(profile),
    '--runbook-db',
    runbookDatabasePathForProfile(profile),
    '--command-data-dir',
    commandDataDirectoryPathForProfile(profile),
    '--command-parser-dir',
    defaultCommandParserDirectoryPath(),
    for (final root in commandAllowedWorkdirsForProfile(profile)) ...[
      '--command-allow-workdir',
      root,
    ],
  ]);
}

/// GatewayRuntimeLaunch derives app launch details from gateway topology data.
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

  /// Command arguments passed to the gateway executable without memory grants.
  List<String> get arguments {
    return _gatewayBaseArguments(this);
  }
}

/// RunbookRuntimeLaunch derives runbook launch and MCP endpoint details.
extension RunbookRuntimeLaunch on RunbookRuntime {
  /// Runbook MCP endpoint exposed directly to the harness.
  String get mcpUrl {
    final uri = Uri.parse(apiBaseUrl);
    return uri.replace(path: '/mcp', query: null).toString();
  }
}

/// Builds standalone runbook launch arguments for the active agent runtime topology.
List<String> runbookArgumentsForProfile(RuntimeProfile profile) {
  final runbook = profile.runbook;
  if (runbook.hostedByHarness) {
    return <String>[];
  }
  return <String>[
    '--addr',
    _listenAddress(runbook.apiBaseUrl, runbook.port),
    '--definitions',
    runbookDefinitionsDirectoryPathForProfile(profile),
    '--db',
    runbookDatabasePathForProfile(profile),
    '--launchpad-db',
    runbookLaunchpadDatabasePathForProfile(profile),
    '--runtime-targets-db',
    runbookRuntimeTargetsDatabasePathForProfile(profile),
    '--harness-context-base-url',
    profile.gateway.contextBaseUrl,
    '--tool',
    profile.harness.toolConfigPath,
    '--command-data-dir',
    commandDataDirectoryPathForProfile(profile),
    '--command-parser-dir',
    defaultCommandParserDirectoryPath(),
    for (final root in commandAllowedWorkdirsForProfile(profile)) ...[
      '--command-allow-workdir',
      root,
    ],
  ];
}

/// Builds gateway launch arguments for the complete active agent runtime topology.
List<String> gatewayArgumentsForProfile(RuntimeProfile profile) {
  return <String>[
    ..._gatewayBaseArguments(profile.gateway),
    if (profile.runbook.enabled) ...<String>[
      '--runbook-base-url',
      profile.runbook.apiBaseUrl,
    ],
    if (profile.runbook.enabled && profile.runbook.hostedByHarness)
      '--harness-embedded-services',
    '--memory-domains-json',
    jsonEncode(_gatewayMemoryDomainJson(profile.memoryServers)),
    '--memory-policy-json',
    jsonEncode(profile.agentMemory.toJson()),
    '--agent-profiles-json',
    jsonEncode(_gatewayAgentProfilesJson(profile)),
    '--memory-services-json',
    jsonEncode(_gatewayMemoryServiceJson(profile.memoryServers)),
  ];
}

/// Builds harness arguments that do not depend on other profile services.
List<String> _harnessBaseArguments(HarnessRuntime harness) {
  return <String>[
    'run',
    '--model',
    harness.modelConfigPath,
    '--agent',
    harness.agentConfigPath,
    '--tool',
    harness.toolConfigPath,
    if (harness.contextApiBaseUrl.isNotEmpty) ...<String>[
      '--context-api-addr',
      _listenAddress(
        harness.contextApiBaseUrl,
        _contextPort(harness.contextApiBaseUrl),
      ),
    ],
    '--',
    'web',
    '--port',
    harness.port.toString(),
    'api',
    '--webui_address',
    harness.webUiAddress,
  ];
}

/// Inserts harness flags before delegated runtime arguments.
List<String> _insertBeforeRuntimeArgs(
  List<String> arguments,
  List<String> flags,
) {
  final boundary = arguments.indexOf('--');
  if (boundary == -1) {
    return <String>[...arguments, ...flags];
  }
  return <String>[
    ...arguments.sublist(0, boundary),
    ...flags,
    ...arguments.sublist(boundary),
  ];
}

/// Returns command roots configured for harness-hosted runbook execution.
List<String> commandAllowedWorkdirsForHarness(HarnessRuntime harness) {
  final explicit = harness.commandAllowedWorkdirs
      .map((root) => root.trim())
      .where((root) => root.isNotEmpty)
      .toList();
  if (explicit.isNotEmpty) {
    return explicit;
  }
  return <String>[defaultCommandAllowedWorkdirForHarness(harness)];
}

/// Returns command roots configured for an agent runtime topology.
List<String> commandAllowedWorkdirsForProfile(RuntimeProfile profile) {
  final explicit = profile.harness.commandAllowedWorkdirs
      .map((root) => root.trim())
      .where((root) => root.isNotEmpty)
      .toList();
  if (explicit.isNotEmpty) {
    return explicit;
  }
  return _uniqueStrings(<String>[
    defaultCommandAllowedWorkdirForProfile(profile),
    defaultWorkspaceCommandAllowedWorkdirForProfile(profile),
  ]);
}

/// Returns the default app-owned command root for an agent runtime topology.
String defaultCommandAllowedWorkdirForProfile(RuntimeProfile profile) {
  return agentCommandWorkdirDirectoryPath(profile.id);
}

/// Returns the configured workspace root for runbook command execution.
String defaultWorkspaceCommandAllowedWorkdirForProfile(RuntimeProfile profile) {
  final workspaceRoot = _localWorkspaceRootForHarness(profile.harness);
  if (workspaceRoot.isEmpty) {
    return '';
  }
  if (_pathBasename(workspaceRoot) == 'agent') {
    final parent = Directory(workspaceRoot).parent.path;
    if (Directory('$parent/agent').existsSync()) {
      return parent;
    }
  }
  return workspaceRoot;
}

/// Returns the app-owned command root used when only harness data is known.
String defaultCommandAllowedWorkdirForHarness(HarnessRuntime _) {
  return '${agentAwesomeDataDirectoryPath()}/command/workdir';
}

/// Encodes the active agent runtime topology as a gateway agent profile registry.
List<Map<String, dynamic>> _gatewayAgentProfilesJson(RuntimeProfile profile) {
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'id': profile.gateway.profileId.trim().isEmpty
          ? profile.id
          : profile.gateway.profileId.trim(),
      'label': profile.label,
      'app_name': profile.harness.appName,
      'user_id': profile.harness.userId,
      ...profile.agentMemory.toJson(),
    },
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

/// Builds gateway arguments that do not depend on agent memory grants.
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

/// Encodes an agent runtime topology as stable, human-editable JSON.
String encodeRuntimeProfileJson(RuntimeProfile profile) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(profile.toJson())}\n';
}

/// Encodes an MCP server runtime config as stable, human-editable JSON.
String encodeMcpServerRuntimeJson(McpServerRuntime server) {
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(server.toJson())}\n';
}

/// RuntimeProfileLoader loads and validates configured or shipped topology.
class RuntimeProfileLoader {
  /// Creates an agent runtime topology loader.
  const RuntimeProfileLoader(this.config);

  /// App configuration containing the optional topology path.
  final AppConfig config;

  /// Loads the topology file selected by AppConfig.
  Future<RuntimeProfile> load() async {
    final file = await resolveProfileFile();
    return loadFile(file);
  }

  /// Loads one topology file and expands supported environment templates.
  Future<RuntimeProfile> loadFile(File file) async {
    final decoded = jsonDecode(_expandTemplate(await file.readAsString()));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Agent runtime must be a JSON object');
    }
    return RuntimeProfile.fromJson(decoded);
  }

  /// Resolves and creates the selected topology file when using defaults.
  Future<File> resolveProfileFile() async {
    final configured = config.runtimeProfilePath.trim();
    if (configured.isNotEmpty) {
      return File(configured);
    }
    final file = File(defaultRuntimeProfilePath());
    if (await file.exists()) {
      return file;
    }
    return writeDefaultRuntimeProfileFile();
  }

  /// Writes the bundled target-state default topology into app-owned storage.
  Future<File> writeDefaultRuntimeProfileFile() async {
    final file = File(defaultRuntimeProfilePath());
    await file.parent.create(recursive: true);
    await file.writeAsString(await loadShippedRuntimeProfileTemplate());
    return file;
  }

  /// Returns the default topology path in the operating system config folder.
  String defaultRuntimeProfilePath() {
    return '${runtimeProfilesDirectoryPath()}/agent_awesome.json';
  }

  /// Returns the shipped topology template path in the workspace.
  String shippedRuntimeProfilePath() {
    return '${config.workspaceRoot}/ui/runtime_topology/agent_awesome.json';
  }

  /// Loads the bundled default topology from the release bundle or app assets.
  Future<String> loadShippedRuntimeProfileTemplate() async {
    final template = File(shippedRuntimeProfilePath());
    if (await template.exists()) {
      return template.readAsString();
    }
    return rootBundle.loadString('runtime_topology/agent_awesome.json');
  }

  /// Expands supported template variables in profile JSON content.
  String _expandTemplate(String profile) {
    var expanded = profile;
    for (final entry in _templateVariables().entries) {
      expanded = expanded.replaceAll('\${${entry.key}}', entry.value);
    }
    return expanded;
  }

  /// Returns template variables available to shipped agent runtime topologies.
  Map<String, String> _templateVariables() {
    final agentApi = Uri.parse(config.agentApiBaseUrl);
    final memoryMcp = Uri.parse(config.memoryMcpUrl);
    final gatewayApi = Uri.parse(config.agentGatewayBaseUrl);
    final contextApi = Uri.parse(config.agentContextApiBaseUrl);
    final sourceControlMcp = Uri.parse(config.sourceControlMcpUrl);
    return <String, String>{
      'AGENTAWESOME_WORKSPACE_ROOT': config.workspaceRoot,
      'AGENTAWESOME_CONFIG_DIR': agentAwesomeConfigDirectoryPath(),
      'AGENTAWESOME_DATA_DIR': agentAwesomeDataDirectoryPath(),
      'AGENT_API_BASE_URL': config.agentApiBaseUrl,
      'AGENT_API_PORT': _portString(agentApi, 8080),
      'AGENT_CONTEXT_API_BASE_URL': config.agentContextApiBaseUrl,
      'AGENT_CONTEXT_API_PORT': _portString(contextApi, 8081),
      'RUNBOOK_API_BASE_URL': _runbookApiBaseUrl(),
      'RUNBOOK_API_PORT': '8092',
      'RUNBOOK_HEALTH_URL': _healthUrl(_runbookApiBaseUrl()),
      'RUNBOOK_DEFINITIONS_DIR': agentRunbookDefinitionsDirectoryPath(
        'agent-awesome',
      ),
      'RUNBOOK_DB_PATH': agentRunbookDatabasePath('agent-awesome'),
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
      'SOURCECONTROL_MCP_URL': config.sourceControlMcpUrl,
      'SOURCECONTROL_MCP_ADDR': sourceControlMcp.authority,
      'SOURCECONTROL_HEALTH_URL': _healthUrl(config.sourceControlMcpUrl),
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

/// Returns the directory where editable agent runtime topologies live.
String runtimeProfilesDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/runtime';
}

/// Returns the directory where editable model config files live.
String modelConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/models';
}

/// Returns the shared model config referenced by agent runtime topologies.
String defaultModelConfigPath() {
  return '${modelConfigsDirectoryPath()}/model.yaml';
}

/// Returns the directory where editable agent config files live.
String agentConfigsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/agents';
}

/// Returns the directory where editable tool config files live.
String toolConfigsDirectoryPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/$aaToolPackageDirectoryName';
}

/// Returns the directory where editable MCP server package configs live.
String mcpConfigsDirectoryPath() {
  return '${agentAwesomeAppConfigDirectoryPath()}/$aaMcpPackageDirectoryName';
}

/// Returns the package config path for one tool package id.
String toolPackageConfigPath(String packageId) {
  return '${toolConfigsDirectoryPath()}/${_safePackageId(packageId)}/$aaToolPackageConfigFilename';
}

/// Returns the package config path for one MCP package id.
String mcpPackageConfigPath(String packageId) {
  return '${mcpConfigsDirectoryPath()}/${_safePackageId(packageId)}/$aaMcpPackageConfigFilename';
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

/// Returns the directory where user-authored runbook YAML files live.
String defaultRunbookDefinitionsDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/runbooks';
}

/// Returns the default SQLite database path for local runbook state.
String defaultRunbookDatabasePath() {
  return '${agentAwesomeDataDirectoryPath()}/runbook/runbook.db';
}

/// Returns the default data directory for the harness-hosted command service.
String defaultCommandDataDirectoryPath() {
  return '${agentAwesomeDataDirectoryPath()}/command';
}

/// Returns the config root containing all local agent bundles.
String agentRuntimeConfigRootDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/agents';
}

/// Returns the config root for one local agent bundle.
String agentRuntimeConfigDirectoryPath(String profileId) {
  return '${agentRuntimeConfigRootDirectoryPath()}/${_safePackageId(profileId)}';
}

/// Returns the data root containing all local agent runtime bundles.
String agentRuntimeDataRootDirectoryPath() {
  return '${agentAwesomeDataDirectoryPath()}/agents';
}

/// Returns the data root for one local agent runtime bundle.
String agentRuntimeDataDirectoryPath(String profileId) {
  return '${agentRuntimeDataRootDirectoryPath()}/${_safePackageId(profileId)}';
}

/// Returns the runbook definition directory for one local agent bundle.
String agentRunbookDefinitionsDirectoryPath(String profileId) {
  return '${agentRuntimeConfigDirectoryPath(profileId)}/runbooks';
}

/// Returns the runbook database path for one local agent runtime bundle.
String agentRunbookDatabasePath(String profileId) {
  return '${agentRuntimeDataDirectoryPath(profileId)}/runbook/runbook.db';
}

/// Returns the launchpad database path for one local agent runtime bundle.
String agentRunbookLaunchpadDatabasePath(String profileId) {
  return '${agentRuntimeDataDirectoryPath(profileId)}/runbook/launchpad.db';
}

/// Returns the runtime target database path for one local agent runtime bundle.
String agentRunbookRuntimeTargetsDatabasePath(String profileId) {
  return '${agentRuntimeDataDirectoryPath(profileId)}/runbook/runtime-targets.db';
}

/// Returns the command data path for one local agent runtime bundle.
String agentCommandDataDirectoryPath(String profileId) {
  return '${agentRuntimeDataDirectoryPath(profileId)}/command';
}

/// Returns the default command workdir for one local agent runtime bundle.
String agentCommandWorkdirDirectoryPath(String profileId) {
  return '${agentRuntimeDataDirectoryPath(profileId)}/workdir';
}

/// Returns the build-output directory for one remote Docker runtime bundle.
String remoteDockerBundleDirectoryPath(String profileId) {
  return 'build/remote-runtime/${_safePackageId(profileId)}';
}

/// Returns the effective runbook definition directory for an agent runtime topology.
String runbookDefinitionsDirectoryPathForProfile(RuntimeProfile profile) {
  final configured = profile.runbook.definitionsDir.trim();
  if (configured.isEmpty ||
      configured == defaultRunbookDefinitionsDirectoryPath() ||
      _isAgentRunbookDefinitionsPath(configured)) {
    return agentRunbookDefinitionsDirectoryPath(profile.id);
  }
  return configured;
}

/// Returns the effective runbook database path for an agent runtime topology.
String runbookDatabasePathForProfile(RuntimeProfile profile) {
  final configured = profile.runbook.dbPath.trim();
  if (configured.isEmpty ||
      configured == defaultRunbookDatabasePath() ||
      _isAgentRunbookDatabasePath(configured)) {
    return agentRunbookDatabasePath(profile.id);
  }
  return configured;
}

/// Returns the effective launchpad database path for an agent runtime topology.
String runbookLaunchpadDatabasePathForProfile(RuntimeProfile profile) {
  return agentRunbookLaunchpadDatabasePath(profile.id);
}

/// Returns the effective runtime target database path for an agent runtime topology.
String runbookRuntimeTargetsDatabasePathForProfile(RuntimeProfile profile) {
  return agentRunbookRuntimeTargetsDatabasePath(profile.id);
}

/// Returns the effective command data directory for an agent runtime topology.
String commandDataDirectoryPathForProfile(RuntimeProfile profile) {
  return agentCommandDataDirectoryPath(profile.id);
}

/// Returns the default parser catalog directory for command output parsers.
String defaultCommandParserDirectoryPath() {
  return '${agentAwesomeConfigDirectoryPath()}/command/parsers';
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

/// Returns a filesystem-safe config package id.
String _safePackageId(String value) {
  final safe = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return safe.isEmpty ? 'default' : safe;
}

/// Reports whether a path belongs to a local agent runbook bundle.
bool _isAgentRunbookDefinitionsPath(String path) {
  final normalized = _normalizedConfigPath(path);
  final root =
      '${_normalizedConfigPath(agentRuntimeConfigRootDirectoryPath())}/';
  return normalized.startsWith(root) && normalized.endsWith('/runbooks');
}

/// Reports whether a path belongs to a local agent runbook database bundle.
bool _isAgentRunbookDatabasePath(String path) {
  final normalized = _normalizedConfigPath(path);
  final root = '${_normalizedConfigPath(agentRuntimeDataRootDirectoryPath())}/';
  return normalized.startsWith(root) &&
      normalized.endsWith('/runbook/runbook.db');
}

/// Returns the workspace root implied by the configured harness directory.
String _localWorkspaceRootForHarness(HarnessRuntime harness) {
  final workingDirectory = harness.workingDirectory.trim();
  if (workingDirectory.isEmpty) {
    return '';
  }
  final root = Directory(workingDirectory).parent;
  if (!_isLocalAgentAwesomeWorkspace(root.path)) {
    return '';
  }
  return root.path;
}

/// Reports whether a directory looks like a local Agent Awesome source bundle.
bool _isLocalAgentAwesomeWorkspace(String path) {
  return Directory('$path/harness').existsSync() &&
      Directory('$path/gateway').existsSync() &&
      Directory('$path/memory').existsSync();
}

/// Returns the final path segment without depending on package:path.
String _pathBasename(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (normalized.isEmpty) {
    return '';
  }
  final index = normalized.lastIndexOf('/');
  return index == -1 ? normalized : normalized.substring(index + 1);
}

/// Returns stable unique non-empty strings.
List<String> _uniqueStrings(List<String> values) {
  final seen = <String>{};
  final results = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) {
      continue;
    }
    results.add(trimmed);
  }
  return results;
}

/// Normalizes path separators for app-owned path classification.
String _normalizedConfigPath(String path) {
  return path.trim().replaceAll('\\', '/');
}

/// Returns the health-check URL for a base service endpoint.
String _healthUrl(String endpoint) {
  final uri = Uri.parse(endpoint);
  return uri.replace(path: '/healthz', query: '').toString();
}

/// Returns the default local runbook API base URL.
String _runbookApiBaseUrl() {
  return 'http://127.0.0.1:8092/api/runbooks';
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
