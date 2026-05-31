/// Defines agent runtime topology data.
library;

import 'json_value.dart';

/// Service topology for one UI session.
class RuntimeProfile {
  /// Creates an immutable agent runtime topology.
  const RuntimeProfile({
    required this.id,
    required this.label,
    required this.harness,
    required this.gateway,
    this.runbook = const RunbookRuntime(
      id: 'runbook',
      label: 'Runbook',
      apiBaseUrl: 'http://127.0.0.1:8092/api/runbooks',
      healthUrl: 'http://127.0.0.1:8092/healthz',
      hostedByHarness: false,
      workingDirectory: '',
      executablePath: '',
      definitionsDir: '',
      dbPath: '',
      port: 8092,
      autoStart: false,
      enabled: false,
    ),
    required this.memoryDomains,
    this.serviceMcpServers = const <McpServerRuntime>[],
    required this.agentMemory,
  });

  /// Stable profile id.
  final String id;

  /// Human-readable profile label.
  final String label;

  /// Harness process and API configuration.
  final HarnessRuntime harness;

  /// Gateway process and API configuration used by every channel client.
  final GatewayRuntime gateway;

  /// Runbook process and API configuration used for durable orchestration.
  final RunbookRuntime runbook;

  /// Configured memory domains available to this agent runtime topology.
  final List<McpServerRuntime> memoryDomains;

  /// Generic managed MCP servers available outside the memory domain boundary.
  final List<McpServerRuntime> serviceMcpServers;

  /// Memory access grants applied to the active agent profile.
  final AgentMemoryRuntime agentMemory;

  /// MCP servers available to the harness and UI.
  List<McpServerRuntime> get mcpServers {
    return <McpServerRuntime>[...memoryDomains, ...serviceMcpServers];
  }

  /// Returns enabled memory MCP servers.
  List<McpServerRuntime> get memoryServers {
    return memoryDomains
        .where((server) => server.enabled && server.kind == 'memory')
        .toList();
  }

  /// Creates an agent runtime topology with selected fields replaced.
  RuntimeProfile copyWith({
    String? id,
    String? label,
    HarnessRuntime? harness,
    GatewayRuntime? gateway,
    RunbookRuntime? runbook,
    List<McpServerRuntime>? memoryDomains,
    List<McpServerRuntime>? serviceMcpServers,
    AgentMemoryRuntime? agentMemory,
  }) {
    return RuntimeProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      harness: harness ?? this.harness,
      gateway: gateway ?? this.gateway,
      runbook: runbook ?? this.runbook,
      memoryDomains: memoryDomains ?? this.memoryDomains,
      serviceMcpServers: serviceMcpServers ?? this.serviceMcpServers,
      agentMemory: agentMemory ?? this.agentMemory,
    );
  }

  /// Encodes this profile to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'harness': harness.toJson(),
      'gateway': gateway.toJson(),
      'runbook': runbook.toJson(),
      'memory_domains': memoryDomains.map((domain) => domain.toJson()).toList(),
      if (serviceMcpServers.isNotEmpty)
        'mcp_servers': serviceMcpServers
            .map((server) => server.toJson())
            .toList(),
      'agent_memory': agentMemory.toJson(),
    };
  }

  /// Parses an agent runtime topology shell from decoded JSON.
  factory RuntimeProfile.fromJson(Map<String, dynamic> json) {
    final domains = jsonObjectList(
      json['memory_domains'],
    ).map(McpServerRuntime.fromJson).toList();
    _validateMemoryDomains(domains);
    final serviceMcpServers = jsonObjectList(
      json['mcp_servers'],
    ).map(McpServerRuntime.fromJson).toList();
    _validateServiceMcpServers(serviceMcpServers, domains);
    final agentMemory = AgentMemoryRuntime.fromJson(
      _requiredMap(json, 'agent_memory'),
    );
    _validateAgentMemory(agentMemory, domains);
    final runbook = RunbookRuntime.fromJson(_requiredMap(json, 'runbook'));
    _validateRunbookRuntime(runbook);
    return RuntimeProfile(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      harness: HarnessRuntime.fromJson(_requiredMap(json, 'harness')),
      gateway: _requiredGateway(_requiredMap(json, 'gateway')),
      runbook: runbook,
      memoryDomains: domains,
      serviceMcpServers: serviceMcpServers,
      agentMemory: agentMemory,
    );
  }
}

/// AgentMemoryRuntime describes domain grants for the active agent profile.
class AgentMemoryRuntime {
  /// Creates immutable memory access grants.
  const AgentMemoryRuntime({
    required this.actor,
    required this.readDomains,
    required this.writeDomains,
    required this.defaultWriteDomain,
    required this.allowedSensitivities,
    this.allowedFlows = const <MemoryDomainFlow>[],
  });

  /// Stable actor principal used at memory service boundaries.
  final String actor;

  /// Domain ids this agent may read.
  final List<String> readDomains;

  /// Domain ids this agent may write.
  final List<String> writeDomains;

  /// Domain id used for automatic session capture.
  final String defaultWriteDomain;

  /// Sensitivity values this agent may retrieve.
  final List<String> allowedSensitivities;

  /// Explicitly allowed source-to-destination memory flows.
  final List<MemoryDomainFlow> allowedFlows;

  /// Encodes this access policy to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'actor': actor,
      'read_domains': readDomains,
      'write_domains': writeDomains,
      'default_write_domain': defaultWriteDomain,
      'allowed_sensitivities': allowedSensitivities,
      if (allowedFlows.isNotEmpty)
        'allowed_flows': allowedFlows.map((flow) => flow.toJson()).toList(),
    };
  }

  /// Parses one agent memory grant set from decoded JSON.
  factory AgentMemoryRuntime.fromJson(Map<String, dynamic> json) {
    return AgentMemoryRuntime(
      actor: _requiredString(json, 'actor'),
      readDomains: stringList(json['read_domains'], trim: true),
      writeDomains: stringList(json['write_domains'], trim: true),
      defaultWriteDomain: _requiredString(json, 'default_write_domain'),
      allowedSensitivities: stringList(
        json['allowed_sensitivities'],
        trim: true,
      ),
      allowedFlows: jsonObjectList(
        json['allowed_flows'],
      ).map(MemoryDomainFlow.fromJson).toList(),
    );
  }
}

/// MemoryDomainFlow allows one source domain to write into one destination.
class MemoryDomainFlow {
  /// Creates an immutable memory-domain information flow grant.
  const MemoryDomainFlow({required this.fromDomain, required this.toDomain});

  /// Source domain id.
  final String fromDomain;

  /// Destination domain id.
  final String toDomain;

  /// Encodes this flow as JSON.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'from': fromDomain, 'to': toDomain};
  }

  /// Parses one flow rule from decoded JSON.
  factory MemoryDomainFlow.fromJson(Map<String, dynamic> json) {
    return MemoryDomainFlow(
      fromDomain: _requiredString(json, 'from'),
      toDomain: _requiredString(json, 'to'),
    );
  }
}

/// GatewayRuntime describes the personal gateway process and active endpoints.
class GatewayRuntime {
  /// Creates an immutable gateway runtime definition.
  const GatewayRuntime({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.healthUrl,
    this.statusUrl = '',
    required this.workingDirectory,
    required this.executablePath,
    required this.harnessBaseUrl,
    required this.contextBaseUrl,
    required this.memoryMcpUrl,
    required this.appName,
    required this.userId,
    this.profileId = '',
    this.authCredential = '',
    this.modelProviderId = '',
    this.modelId = '',
    required this.port,
    required this.autoStart,
    required this.enabled,
  });

  /// Stable gateway id.
  final String id;

  /// Human-readable gateway label.
  final String label;

  /// Gateway API base URL consumed by UI chat clients.
  final String apiBaseUrl;

  /// Gateway health URL used before and after launching.
  final String healthUrl;

  /// Gateway beta status URL for operator checks.
  final String statusUrl;

  /// Working directory used when launching the gateway executable.
  final String workingDirectory;

  /// Gateway executable or start-script path.
  final String executablePath;

  /// Upstream harness API base URL.
  final String harnessBaseUrl;

  /// Upstream harness context API base URL.
  final String contextBaseUrl;

  /// Memory MCP URL reported to the gateway.
  final String memoryMcpUrl;

  /// Assistant app name passed through gateway status and policy.
  final String appName;

  /// Assistant user id passed through gateway status and policy.
  final String userId;

  /// Server-side gateway routing id selected for this UI runtime.
  final String profileId;

  /// Credential reference used to resolve the gateway bearer token.
  final String authCredential;

  /// Non-secret model provider id shown in beta status.
  final String modelProviderId;

  /// Non-secret model id shown in beta status.
  final String modelId;

  /// Gateway listen port.
  final int port;

  /// Whether the UI should start this gateway.
  final bool autoStart;

  /// Whether the UI should use this gateway for assistant traffic.
  final bool enabled;

  /// Creates a gateway runtime with selected fields replaced.
  GatewayRuntime copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    String? healthUrl,
    String? statusUrl,
    String? workingDirectory,
    String? executablePath,
    String? harnessBaseUrl,
    String? contextBaseUrl,
    String? memoryMcpUrl,
    String? appName,
    String? userId,
    String? profileId,
    String? authCredential,
    String? modelProviderId,
    String? modelId,
    int? port,
    bool? autoStart,
    bool? enabled,
  }) {
    return GatewayRuntime(
      id: id ?? this.id,
      label: label ?? this.label,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      healthUrl: healthUrl ?? this.healthUrl,
      statusUrl: statusUrl ?? this.statusUrl,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      executablePath: executablePath ?? this.executablePath,
      harnessBaseUrl: harnessBaseUrl ?? this.harnessBaseUrl,
      contextBaseUrl: contextBaseUrl ?? this.contextBaseUrl,
      memoryMcpUrl: memoryMcpUrl ?? this.memoryMcpUrl,
      appName: appName ?? this.appName,
      userId: userId ?? this.userId,
      profileId: profileId ?? this.profileId,
      authCredential: authCredential ?? this.authCredential,
      modelProviderId: modelProviderId ?? this.modelProviderId,
      modelId: modelId ?? this.modelId,
      port: port ?? this.port,
      autoStart: autoStart ?? this.autoStart,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Encodes this gateway runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'api_base_url': apiBaseUrl,
      'health_url': healthUrl,
      if (statusUrl.isNotEmpty) 'status_url': statusUrl,
      'working_directory': workingDirectory,
      'executable_path': executablePath,
      'harness_base_url': harnessBaseUrl,
      'context_base_url': contextBaseUrl,
      'memory_mcp_url': memoryMcpUrl,
      'app_name': appName,
      'user_id': userId,
      if (profileId.isNotEmpty) 'profile_id': profileId,
      if (authCredential.isNotEmpty) 'auth_credential': authCredential,
      if (modelProviderId.isNotEmpty) 'model_provider_id': modelProviderId,
      if (modelId.isNotEmpty) 'model_id': modelId,
      'port': port,
      'auto_start': autoStart,
      'enabled': enabled,
    };
  }

  /// Parses gateway runtime JSON from explicit profile values.
  factory GatewayRuntime.fromJson(Map<String, dynamic> json) {
    final harnessBaseUrl = _requiredString(json, 'harness_base_url');
    final contextBaseUrl = _optionalString(json['context_base_url']);
    return GatewayRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      apiBaseUrl: _requiredString(json, 'api_base_url'),
      healthUrl: _requiredString(json, 'health_url'),
      statusUrl: _optionalString(json['status_url']),
      workingDirectory: _requiredString(json, 'working_directory'),
      executablePath: _requiredString(json, 'executable_path'),
      harnessBaseUrl: harnessBaseUrl,
      contextBaseUrl: contextBaseUrl.isEmpty
          ? _defaultContextBaseUrl(harnessBaseUrl)
          : contextBaseUrl,
      memoryMcpUrl: _requiredString(json, 'memory_mcp_url'),
      appName: _requiredString(json, 'app_name'),
      userId: _requiredString(json, 'user_id'),
      profileId: _optionalString(json['profile_id']),
      authCredential: _optionalString(json['auth_credential']),
      modelProviderId: _optionalString(json['model_provider_id']),
      modelId: _optionalString(json['model_id']),
      port: _requiredInt(json, 'port'),
      autoStart: _requiredBool(json, 'auto_start'),
      enabled: _requiredBool(json, 'enabled'),
    );
  }
}

/// RunbookRuntime describes the runbook orchestration service process.
class RunbookRuntime {
  /// Creates an immutable runbook runtime definition.
  const RunbookRuntime({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.healthUrl,
    this.hostedByHarness = false,
    required this.workingDirectory,
    required this.executablePath,
    required this.definitionsDir,
    required this.dbPath,
    required this.port,
    required this.autoStart,
    required this.enabled,
  });

  /// Stable runbook service id.
  final String id;

  /// Human-readable runbook service label.
  final String label;

  /// Runbook REST API base URL.
  final String apiBaseUrl;

  /// Runbook health URL used before and after launching.
  final String healthUrl;

  /// Whether the harness process owns this runbook listener.
  final bool hostedByHarness;

  /// Working directory for an externally launched runbook service.
  final String workingDirectory;

  /// Runbook executable or start-script path.
  final String executablePath;

  /// Directory containing user-authored runbook YAML files.
  final String definitionsDir;

  /// SQLite database path for durable runbook state.
  final String dbPath;

  /// Runbook service listen port.
  final int port;

  /// Whether the UI should start an external runbook service process.
  final bool autoStart;

  /// Whether this profile exposes runbook orchestration.
  final bool enabled;

  /// Creates a runbook runtime with selected fields replaced.
  RunbookRuntime copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    String? healthUrl,
    bool? hostedByHarness,
    String? workingDirectory,
    String? executablePath,
    String? definitionsDir,
    String? dbPath,
    int? port,
    bool? autoStart,
    bool? enabled,
  }) {
    return RunbookRuntime(
      id: id ?? this.id,
      label: label ?? this.label,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      healthUrl: healthUrl ?? this.healthUrl,
      hostedByHarness: hostedByHarness ?? this.hostedByHarness,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      executablePath: executablePath ?? this.executablePath,
      definitionsDir: definitionsDir ?? this.definitionsDir,
      dbPath: dbPath ?? this.dbPath,
      port: port ?? this.port,
      autoStart: autoStart ?? this.autoStart,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Encodes this runbook runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'api_base_url': apiBaseUrl,
      'health_url': healthUrl,
      'hosted_by_harness': hostedByHarness,
      'working_directory': workingDirectory,
      'executable_path': executablePath,
      'definitions_dir': definitionsDir,
      'db_path': dbPath,
      'port': port,
      'auto_start': autoStart,
      'enabled': enabled,
    };
  }

  /// Parses runbook runtime JSON from explicit profile values.
  factory RunbookRuntime.fromJson(Map<String, dynamic> json) {
    return RunbookRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      apiBaseUrl: _requiredString(json, 'api_base_url'),
      healthUrl: _requiredString(json, 'health_url'),
      hostedByHarness: _optionalBool(json['hosted_by_harness']),
      workingDirectory: _optionalString(json['working_directory']),
      executablePath: _optionalString(json['executable_path']),
      definitionsDir: _optionalString(json['definitions_dir']),
      dbPath: _optionalString(json['db_path']),
      port: _requiredInt(json, 'port'),
      autoStart: _requiredBool(json, 'auto_start'),
      enabled: _requiredBool(json, 'enabled'),
    );
  }
}

/// HarnessRuntime describes the assistant harness process and active config bundle.
class HarnessRuntime {
  /// Creates an immutable harness runtime definition.
  const HarnessRuntime({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.contextApiBaseUrl,
    required this.appName,
    required this.userId,
    required this.workingDirectory,
    required this.executablePath,
    required this.modelConfigPath,
    required this.agentConfigPath,
    required this.toolConfigPath,
    this.commandAllowedWorkdirs = const <String>[],
    required this.port,
    required this.autoStart,
  });

  /// Stable harness id.
  final String id;

  /// Human-readable harness label.
  final String label;

  /// Assistant API base URL.
  final String apiBaseUrl;

  /// Harness-owned context API base URL.
  final String contextApiBaseUrl;

  /// Assistant app name hosted by this harness.
  final String appName;

  /// Assistant user id used for session APIs.
  final String userId;

  /// Working directory used when launching the harness executable.
  final String workingDirectory;

  /// Harness executable or start-script path.
  final String executablePath;

  /// Model config path passed to the harness.
  final String modelConfigPath;

  /// Agent config path passed to the harness.
  final String agentConfigPath;

  /// Tool config path passed to the harness.
  final String toolConfigPath;

  /// Command working-directory roots allowed for runbook command actions.
  final List<String> commandAllowedWorkdirs;

  /// Web API listen port.
  final int port;

  /// Whether the UI should start this harness.
  final bool autoStart;

  /// Creates a harness runtime with selected fields replaced.
  HarnessRuntime copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    String? contextApiBaseUrl,
    String? appName,
    String? userId,
    String? workingDirectory,
    String? executablePath,
    String? modelConfigPath,
    String? agentConfigPath,
    String? toolConfigPath,
    List<String>? commandAllowedWorkdirs,
    int? port,
    bool? autoStart,
  }) {
    return HarnessRuntime(
      id: id ?? this.id,
      label: label ?? this.label,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      contextApiBaseUrl: contextApiBaseUrl ?? this.contextApiBaseUrl,
      appName: appName ?? this.appName,
      userId: userId ?? this.userId,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      executablePath: executablePath ?? this.executablePath,
      modelConfigPath: modelConfigPath ?? this.modelConfigPath,
      agentConfigPath: agentConfigPath ?? this.agentConfigPath,
      toolConfigPath: toolConfigPath ?? this.toolConfigPath,
      commandAllowedWorkdirs:
          commandAllowedWorkdirs ?? this.commandAllowedWorkdirs,
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
      'context_api_base_url': contextApiBaseUrl,
      'app_name': appName,
      'user_id': userId,
      'working_directory': workingDirectory,
      'executable_path': executablePath,
      'model_config': modelConfigPath,
      'agent_config': agentConfigPath,
      'tool_config': toolConfigPath,
      if (commandAllowedWorkdirs.isNotEmpty)
        'command_allowed_workdirs': commandAllowedWorkdirs,
      'port': port,
      'auto_start': autoStart,
    };
  }

  /// Parses harness runtime JSON from explicit profile values.
  factory HarnessRuntime.fromJson(Map<String, dynamic> json) {
    final apiBaseUrl = _requiredString(json, 'api_base_url');
    final contextApiBaseUrl = _optionalString(json['context_api_base_url']);
    return HarnessRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      apiBaseUrl: apiBaseUrl,
      contextApiBaseUrl: contextApiBaseUrl.isEmpty
          ? _defaultContextBaseUrl(apiBaseUrl)
          : contextApiBaseUrl,
      appName: _requiredString(json, 'app_name'),
      userId: _requiredString(json, 'user_id'),
      workingDirectory: _requiredString(json, 'working_directory'),
      executablePath: _requiredString(json, 'executable_path'),
      modelConfigPath: _requiredString(json, 'model_config'),
      agentConfigPath: _requiredString(json, 'agent_config'),
      toolConfigPath: _requiredString(json, 'tool_config'),
      commandAllowedWorkdirs: stringList(
        json['command_allowed_workdirs'],
        trim: true,
      ),
      port: _requiredInt(json, 'port'),
      autoStart: _requiredBool(json, 'auto_start'),
    );
  }
}

/// McpServerRuntime describes one managed MCP server.
class McpServerRuntime {
  /// Creates an immutable MCP server runtime definition.
  const McpServerRuntime({
    required this.id,
    required this.label,
    required this.kind,
    required this.endpoint,
    required this.healthUrl,
    required this.workingDirectory,
    required this.executablePath,
    required this.dbPath,
    required this.dataDir,
    required this.arguments,
    required this.autoStart,
    required this.enabled,
  });

  /// Stable MCP server id.
  final String id;

  /// Human-readable MCP server label.
  final String label;

  /// Logical server kind, such as memory.
  final String kind;

  /// Streamable HTTP MCP endpoint.
  final String endpoint;

  /// Health URL used before and after launching.
  final String healthUrl;

  /// Working directory used when launching the local server executable.
  final String workingDirectory;

  /// Local server executable or start-script path.
  final String executablePath;

  /// Domain-specific database path for managed memory services.
  final String dbPath;

  /// Domain-specific artifact directory for managed memory services.
  final String dataDir;

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
      executablePath: _optionalString(json['executable_path']),
      dbPath: _optionalString(json['db_path']),
      dataDir: _optionalString(json['data_dir']),
      arguments: stringList(json['arguments']),
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
    String? executablePath,
    String? dbPath,
    String? dataDir,
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
      executablePath: executablePath ?? this.executablePath,
      dbPath: dbPath ?? this.dbPath,
      dataDir: dataDir ?? this.dataDir,
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
      'executable_path': executablePath,
      'db_path': dbPath,
      'data_dir': dataDir,
      'arguments': arguments,
      'auto_start': autoStart,
      'enabled': enabled,
    };
  }
}

/// Returns the default context API base URL beside a harness API URL.
String _defaultContextBaseUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  final port = uri.hasPort ? uri.port + 1 : 8081;
  return uri.replace(path: '/api/context', query: null, port: port).toString();
}

/// Reads a required nested JSON object from a topology map.
Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Agent runtime field "$field" must be an object');
}

/// Parses and validates the required gateway runtime object.
GatewayRuntime _requiredGateway(Map<String, dynamic> value) {
  final gateway = GatewayRuntime.fromJson(value);
  if (!gateway.enabled) {
    throw const FormatException('Agent runtime gateway must be enabled');
  }
  return gateway;
}

/// Validates configured memory domains as target-state topology data.
void _validateMemoryDomains(List<McpServerRuntime> domains) {
  if (domains.isEmpty) {
    throw const FormatException(
      'Agent runtime field "memory_domains" must not be empty',
    );
  }
  final ids = <String>{};
  final managedEndpoints = <String, String>{};
  final managedDatabasePaths = <String, String>{};
  final managedDataDirectories = <String, String>{};
  for (final domain in domains) {
    _validateSafeId(domain.id, 'memory domain id');
    if (!ids.add(domain.id)) {
      throw FormatException('Duplicate memory domain id "${domain.id}"');
    }
    if (domain.kind != 'memory') {
      throw FormatException(
        'Memory domain "${domain.id}" must have kind "memory"',
      );
    }
    if (domain.autoStart && domain.dataDir.trim().isEmpty) {
      throw FormatException(
        'Managed memory domain "${domain.id}" requires data_dir',
      );
    }
    if (domain.autoStart &&
        (domain.workingDirectory.trim().isEmpty ||
            domain.executablePath.trim().isEmpty)) {
      throw FormatException(
        'Managed memory domain "${domain.id}" requires working_directory and executable_path',
      );
    }
    if (domain.autoStart) {
      _rememberUnique(
        managedEndpoints,
        _endpointKey(domain.endpoint),
        domain.id,
        'Managed memory domains',
      );
      _rememberUnique(
        managedEndpoints,
        _endpointKey(domain.healthUrl),
        domain.id,
        'Managed memory domain health URLs',
      );
      if (domain.dbPath.trim().isNotEmpty) {
        _rememberUnique(
          managedDatabasePaths,
          domain.dbPath,
          domain.id,
          'Managed memory domain database paths',
        );
      }
      _rememberUnique(
        managedDataDirectories,
        domain.dataDir,
        domain.id,
        'Managed memory domain data directories',
      );
    }
  }
}

/// Validates generic managed MCP servers as profile-owned service data.
void _validateServiceMcpServers(
  List<McpServerRuntime> servers,
  List<McpServerRuntime> memoryDomains,
) {
  final ids = <String>{for (final domain in memoryDomains) domain.id};
  final managedEndpoints = <String, String>{
    for (final domain in memoryDomains)
      if (domain.autoStart) _endpointKey(domain.endpoint): domain.id,
    for (final domain in memoryDomains)
      if (domain.autoStart) _endpointKey(domain.healthUrl): domain.id,
  };
  for (final server in servers) {
    _validateSafeId(server.id, 'MCP server id');
    if (!ids.add(server.id)) {
      throw FormatException('Duplicate MCP server id "${server.id}"');
    }
    if (server.kind == 'memory') {
      throw FormatException(
        'MCP server "${server.id}" must use memory_domains for kind "memory"',
      );
    }
    if (server.enabled &&
        (server.endpoint.trim().isEmpty || server.healthUrl.trim().isEmpty)) {
      throw FormatException(
        'Enabled MCP server "${server.id}" requires endpoint and health_url',
      );
    }
    if (server.autoStart &&
        (server.workingDirectory.trim().isEmpty ||
            server.executablePath.trim().isEmpty)) {
      throw FormatException(
        'Managed MCP server "${server.id}" requires working_directory and executable_path',
      );
    }
    if (server.autoStart) {
      _rememberUnique(
        managedEndpoints,
        _endpointKey(server.endpoint),
        server.id,
        'Managed MCP server endpoints',
      );
      _rememberUnique(
        managedEndpoints,
        _endpointKey(server.healthUrl),
        server.id,
        'Managed MCP server health URLs',
      );
    }
  }
}

/// Validates runbook service settings as profile-owned orchestration data.
void _validateRunbookRuntime(RunbookRuntime runbook) {
  _validateSafeId(runbook.id, 'runbook id');
  if (!runbook.enabled) {
    return;
  }
  if (runbook.apiBaseUrl.trim().isEmpty || runbook.healthUrl.trim().isEmpty) {
    throw const FormatException(
      'Enabled runbook runtime requires api_base_url and health_url',
    );
  }
  if (runbook.hostedByHarness &&
      (runbook.definitionsDir.trim().isEmpty ||
          runbook.dbPath.trim().isEmpty)) {
    throw const FormatException(
      'Harness-hosted runbook runtime requires definitions_dir and db_path',
    );
  }
  if (!runbook.hostedByHarness &&
      runbook.autoStart &&
      (runbook.workingDirectory.trim().isEmpty ||
          runbook.executablePath.trim().isEmpty ||
          runbook.definitionsDir.trim().isEmpty ||
          runbook.dbPath.trim().isEmpty)) {
    throw const FormatException(
      'Managed runbook runtime requires working_directory, executable_path, definitions_dir, and db_path',
    );
  }
}

/// Validates agent memory grants against configured domain ids.
void _validateAgentMemory(
  AgentMemoryRuntime memory,
  List<McpServerRuntime> domains,
) {
  _validateSafeId(memory.actor.replaceAll(':', '-'), 'agent memory actor');
  final ids = domains.map((domain) => domain.id).toSet();
  final enabledIds = domains
      .where((domain) => domain.enabled)
      .map((domain) => domain.id)
      .toSet();
  if (memory.readDomains.isEmpty) {
    throw const FormatException('agent_memory.read_domains must not be empty');
  }
  if (memory.writeDomains.isEmpty) {
    throw const FormatException('agent_memory.write_domains must not be empty');
  }
  for (final domain in <String>[
    ...memory.readDomains,
    ...memory.writeDomains,
    memory.defaultWriteDomain,
    for (final flow in memory.allowedFlows) ...<String>[
      flow.fromDomain,
      flow.toDomain,
    ],
  ]) {
    _validateSafeId(domain, 'agent memory domain grant');
    if (!ids.contains(domain)) {
      throw FormatException('Unknown memory domain grant "$domain"');
    }
    if (!enabledIds.contains(domain)) {
      throw FormatException('Memory domain grant "$domain" is disabled');
    }
  }
  if (!memory.writeDomains.contains(memory.defaultWriteDomain)) {
    throw FormatException(
      'default_write_domain "${memory.defaultWriteDomain}" is not writable',
    );
  }
  for (final flow in memory.allowedFlows) {
    if (!memory.readDomains.contains(flow.fromDomain)) {
      throw FormatException(
        'allowed flow source "${flow.fromDomain}" is not readable',
      );
    }
    if (!memory.writeDomains.contains(flow.toDomain)) {
      throw FormatException(
        'allowed flow target "${flow.toDomain}" is not writable',
      );
    }
  }
}

/// Remembers one non-empty domain-owned value and rejects duplicate ownership.
void _rememberUnique(
  Map<String, String> seen,
  String value,
  String domainId,
  String label,
) {
  final key = value.trim();
  if (key.isEmpty) {
    return;
  }
  final owner = seen[key];
  if (owner != null && owner != domainId) {
    throw FormatException(
      '$label duplicate "$key" for "$owner" and "$domainId"',
    );
  }
  seen[key] = domainId;
}

/// Returns a duplicate-detection key for one endpoint URI.
String _endpointKey(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) {
    return value.trim();
  }
  return uri.replace(query: '', fragment: '').toString();
}

/// Validates one config-owned identifier.
void _validateSafeId(String value, String label) {
  final id = value.trim();
  final pattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');
  if (!pattern.hasMatch(id)) {
    throw FormatException('$label "$value" is not a safe id');
  }
}

/// Reads a required string field from a topology map.
String _requiredString(Map<String, dynamic> json, String field) {
  final text = _optionalString(json[field]);
  if (text.isEmpty) {
    throw FormatException('Agent runtime field "$field" is required');
  }
  return text;
}

/// Converts an optional profile field to a string.
String _optionalString(dynamic value) {
  return stringValue(value);
}

/// Reads a required integer field from a topology map.
int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is int) {
    return value;
  }
  final parsed = int.tryParse(_optionalString(value));
  if (parsed == null) {
    throw FormatException('Agent runtime field "$field" must be an integer');
  }
  return parsed;
}

/// Reads a required boolean field from a topology map.
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
  throw FormatException('Agent runtime field "$field" must be a boolean');
}

/// Converts an optional profile field to a boolean with a false default.
bool _optionalBool(dynamic value) {
  if (value == null) {
    return false;
  }
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
  throw const FormatException('Agent runtime optional boolean is invalid');
}
