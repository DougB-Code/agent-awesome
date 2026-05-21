/// Defines runtime profile topology data.
library;

import 'json_value.dart';

/// RuntimeProfile describes the complete service topology for one UI session.
class RuntimeProfile {
  /// Creates an immutable runtime profile.
  const RuntimeProfile({
    required this.id,
    required this.label,
    required this.harness,
    required this.gateway,
    this.workflow = const WorkflowRuntime(
      id: 'workflow',
      label: 'Workflow',
      apiBaseUrl: 'http://127.0.0.1:8092/api/workflows',
      healthUrl: 'http://127.0.0.1:8092/healthz',
      hostedByHarness: false,
      workingDirectory: '',
      packagePath: '',
      definitionsDir: '',
      dbPath: '',
      port: 8092,
      autoStart: false,
      enabled: false,
    ),
    required this.memoryDomains,
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

  /// Workflow process and API configuration used for durable orchestration.
  final WorkflowRuntime workflow;

  /// Configured memory domains available to this runtime profile.
  final List<McpServerRuntime> memoryDomains;

  /// Memory access grants applied to the active agent profile.
  final AgentMemoryRuntime agentMemory;

  /// MCP servers available to the harness and UI.
  List<McpServerRuntime> get mcpServers {
    return memoryDomains;
  }

  /// Returns enabled memory MCP servers.
  List<McpServerRuntime> get memoryServers {
    return memoryDomains
        .where((server) => server.enabled && server.kind == 'memory')
        .toList();
  }

  /// Creates a runtime profile with selected fields replaced.
  RuntimeProfile copyWith({
    String? id,
    String? label,
    HarnessRuntime? harness,
    GatewayRuntime? gateway,
    WorkflowRuntime? workflow,
    List<McpServerRuntime>? memoryDomains,
    AgentMemoryRuntime? agentMemory,
  }) {
    return RuntimeProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      harness: harness ?? this.harness,
      gateway: gateway ?? this.gateway,
      workflow: workflow ?? this.workflow,
      memoryDomains: memoryDomains ?? this.memoryDomains,
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
      'workflow': workflow.toJson(),
      'memory_domains': memoryDomains.map((domain) => domain.toJson()).toList(),
      'agent_memory': agentMemory.toJson(),
    };
  }

  /// Parses a runtime profile shell from decoded JSON.
  factory RuntimeProfile.fromJson(Map<String, dynamic> json) {
    final domains = jsonObjectList(
      json['memory_domains'],
    ).map(McpServerRuntime.fromJson).toList();
    _validateMemoryDomains(domains);
    final agentMemory = AgentMemoryRuntime.fromJson(
      _requiredMap(json, 'agent_memory'),
    );
    _validateAgentMemory(agentMemory, domains);
    final workflow = WorkflowRuntime.fromJson(_requiredMap(json, 'workflow'));
    _validateWorkflowRuntime(workflow);
    return RuntimeProfile(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      harness: HarnessRuntime.fromJson(_requiredMap(json, 'harness')),
      gateway: _requiredGateway(_requiredMap(json, 'gateway')),
      workflow: workflow,
      memoryDomains: domains,
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
    required this.packagePath,
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

  /// Directory where the Go gateway package is built and run.
  final String workingDirectory;

  /// Go package path for the gateway command.
  final String packagePath;

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

  /// Server-side gateway profile selected for this UI runtime.
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

  /// Encodes this gateway runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'api_base_url': apiBaseUrl,
      'health_url': healthUrl,
      if (statusUrl.isNotEmpty) 'status_url': statusUrl,
      'working_directory': workingDirectory,
      'package_path': packagePath,
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
      packagePath: _requiredString(json, 'package_path'),
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

/// WorkflowRuntime describes the workflow orchestration service process.
class WorkflowRuntime {
  /// Creates an immutable workflow runtime definition.
  const WorkflowRuntime({
    required this.id,
    required this.label,
    required this.apiBaseUrl,
    required this.healthUrl,
    this.hostedByHarness = false,
    required this.workingDirectory,
    required this.packagePath,
    required this.definitionsDir,
    required this.dbPath,
    required this.port,
    required this.autoStart,
    required this.enabled,
  });

  /// Stable workflow service id.
  final String id;

  /// Human-readable workflow service label.
  final String label;

  /// Workflow REST API base URL.
  final String apiBaseUrl;

  /// Workflow health URL used before and after launching.
  final String healthUrl;

  /// Whether the harness process owns this workflow listener.
  final bool hostedByHarness;

  /// Working directory for an externally launched workflow service.
  final String workingDirectory;

  /// Package or command path for an externally launched workflow service.
  final String packagePath;

  /// Directory containing user-authored workflow YAML files.
  final String definitionsDir;

  /// SQLite database path for durable workflow state.
  final String dbPath;

  /// Workflow service listen port.
  final int port;

  /// Whether the UI should start an external workflow service process.
  final bool autoStart;

  /// Whether this profile exposes workflow orchestration.
  final bool enabled;

  /// Encodes this workflow runtime to explicit JSON values.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'api_base_url': apiBaseUrl,
      'health_url': healthUrl,
      'hosted_by_harness': hostedByHarness,
      'working_directory': workingDirectory,
      'package_path': packagePath,
      'definitions_dir': definitionsDir,
      'db_path': dbPath,
      'port': port,
      'auto_start': autoStart,
      'enabled': enabled,
    };
  }

  /// Parses workflow runtime JSON from explicit profile values.
  factory WorkflowRuntime.fromJson(Map<String, dynamic> json) {
    return WorkflowRuntime(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      apiBaseUrl: _requiredString(json, 'api_base_url'),
      healthUrl: _requiredString(json, 'health_url'),
      hostedByHarness: _optionalBool(json['hosted_by_harness']),
      workingDirectory: _optionalString(json['working_directory']),
      packagePath: _optionalString(json['package_path']),
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

  /// Assistant API base URL.
  final String apiBaseUrl;

  /// Harness-owned context API base URL.
  final String contextApiBaseUrl;

  /// Assistant app name hosted by this harness.
  final String appName;

  /// Assistant user id used for session APIs.
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

  /// Creates a harness runtime with selected fields replaced.
  HarnessRuntime copyWith({
    String? id,
    String? label,
    String? apiBaseUrl,
    String? contextApiBaseUrl,
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
      contextApiBaseUrl: contextApiBaseUrl ?? this.contextApiBaseUrl,
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
      'context_api_base_url': contextApiBaseUrl,
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
      packagePath: _requiredString(json, 'package_path'),
      modelConfigPath: _requiredString(json, 'model_config'),
      agentConfigPath: _requiredString(json, 'agent_config'),
      toolConfigPath: _requiredString(json, 'tool_config'),
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
    required this.packagePath,
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

  /// Directory where the Go package is built and run.
  final String workingDirectory;

  /// Go package path for managed local servers.
  final String packagePath;

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
      packagePath: _optionalString(json['package_path']),
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
    String? packagePath,
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
      packagePath: packagePath ?? this.packagePath,
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
      'package_path': packagePath,
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

/// Reads a required nested JSON object from a profile map.
Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Runtime profile field "$field" must be an object');
}

/// Parses and validates the required gateway runtime object.
GatewayRuntime _requiredGateway(Map<String, dynamic> value) {
  final gateway = GatewayRuntime.fromJson(value);
  if (!gateway.enabled) {
    throw const FormatException('Runtime profile gateway must be enabled');
  }
  return gateway;
}

/// Validates configured memory domains as target-state profile data.
void _validateMemoryDomains(List<McpServerRuntime> domains) {
  if (domains.isEmpty) {
    throw const FormatException(
      'Runtime profile field "memory_domains" must not be empty',
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
    if (domain.autoStart &&
        (domain.dbPath.trim().isEmpty || domain.dataDir.trim().isEmpty)) {
      throw FormatException(
        'Managed memory domain "${domain.id}" requires db_path and data_dir',
      );
    }
    if (domain.autoStart &&
        (domain.workingDirectory.trim().isEmpty ||
            domain.packagePath.trim().isEmpty)) {
      throw FormatException(
        'Managed memory domain "${domain.id}" requires working_directory and package_path',
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
      _rememberUnique(
        managedDatabasePaths,
        domain.dbPath,
        domain.id,
        'Managed memory domain database paths',
      );
      _rememberUnique(
        managedDataDirectories,
        domain.dataDir,
        domain.id,
        'Managed memory domain data directories',
      );
    }
  }
}

/// Validates workflow service settings as profile-owned orchestration data.
void _validateWorkflowRuntime(WorkflowRuntime workflow) {
  _validateSafeId(workflow.id, 'workflow id');
  if (!workflow.enabled) {
    return;
  }
  if (workflow.apiBaseUrl.trim().isEmpty || workflow.healthUrl.trim().isEmpty) {
    throw const FormatException(
      'Enabled workflow runtime requires api_base_url and health_url',
    );
  }
  if (workflow.hostedByHarness &&
      (workflow.definitionsDir.trim().isEmpty ||
          workflow.dbPath.trim().isEmpty)) {
    throw const FormatException(
      'Harness-hosted workflow runtime requires definitions_dir and db_path',
    );
  }
  if (!workflow.hostedByHarness &&
      workflow.autoStart &&
      (workflow.workingDirectory.trim().isEmpty ||
          workflow.packagePath.trim().isEmpty ||
          workflow.definitionsDir.trim().isEmpty ||
          workflow.dbPath.trim().isEmpty)) {
    throw const FormatException(
      'Managed workflow runtime requires working_directory, package_path, definitions_dir, and db_path',
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

/// Reads a required string field from a profile map.
String _requiredString(Map<String, dynamic> json, String field) {
  final text = _optionalString(json[field]);
  if (text.isEmpty) {
    throw FormatException('Runtime profile field "$field" is required');
  }
  return text;
}

/// Converts an optional profile field to a string.
String _optionalString(dynamic value) {
  return stringValue(value);
}

/// Reads a required integer field from a profile map.
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

/// Reads a required boolean field from a profile map.
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
  throw const FormatException('Runtime profile optional boolean is invalid');
}
