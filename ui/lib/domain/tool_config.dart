/// Parses and writes harness tool configuration files.
library;

import 'package:yaml/yaml.dart';

import 'config_yaml.dart';
import 'json_value.dart';
import 'runtime_profile.dart';

/// Tools currently exposed by the graph-backed memory MCP endpoint.
const List<String> graphBackedMcpToolNames = <String>[
  'remember',
  'save_memory_candidate',
  'search_memory',
  'search_sources',
  'load_entity_page',
  'load_timeline',
  'refresh_compiled_page',
  'repair_memory_record',
  'submit_memory_correction',
  'query_context_graph',
  'mutate_context_graph',
  'create_task',
  'get_task',
  'list_tasks',
  'task_graph_projection',
  'project_executive_summary',
  'explain_executive_summary_item',
  'update_task',
  'complete_task',
  'cancel_task',
  'delete_task',
  'link_task_memory',
  'list_task_relations',
  'traverse_task_relations',
  'upsert_task_relation',
  'delete_task_relation',
];

/// Graph-backed memory tools that should pause for human confirmation.
const List<String> graphBackedMcpConfirmationToolNames = <String>[
  'remember',
  'save_memory_candidate',
  'refresh_compiled_page',
  'repair_memory_record',
  'submit_memory_correction',
  'query_context_graph',
  'mutate_context_graph',
  'create_task',
  'update_task',
  'complete_task',
  'cancel_task',
  'delete_task',
  'link_task_memory',
  'upsert_task_relation',
  'delete_task_relation',
];

/// Graph-backed memory tools that only read from memory domains.
const List<String> graphBackedMcpReadOnlyToolNames = <String>[
  'search_memory',
  'search_sources',
  'load_entity_page',
  'load_timeline',
  'query_context_graph',
  'get_task',
  'list_tasks',
  'task_graph_projection',
  'project_executive_summary',
  'explain_executive_summary_item',
  'list_task_relations',
  'traverse_task_relations',
];

/// Workflow MCP tools exposed by the workflow service.
const List<String> workflowMcpToolNames = <String>[
  'workflow_list',
  'workflow_describe',
  'workflow_start',
  'workflow_status',
  'workflow_signal',
  'workflow_cancel',
  'workflow_history',
  'workflow_action_types',
  'workflow_draft_create',
  'workflow_draft_update',
  'workflow_draft_validate',
  'workflow_draft_publish',
];

/// ToolConfigDocument represents one harness tool config YAML file.
class ToolConfigDocument {
  /// Creates a tool config document.
  const ToolConfigDocument({
    required this.localExec,
    required this.mcp,
    this.extra = const <String, dynamic>{},
  });

  /// Local OS command tool settings.
  final LocalExecToolConfig localExec;

  /// MCP toolset settings.
  final McpToolConfig mcp;

  /// Top-level fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses YAML or JSON tool config content.
  factory ToolConfigDocument.parse(String content) {
    final decoded = plainYamlValue(loadYaml(content));
    if (decoded is! Map<String, dynamic>) {
      return emptyToolConfigDocument();
    }
    final extra = Map<String, dynamic>.from(decoded)
      ..remove('local-exec')
      ..remove('local_exec')
      ..remove('mcp');
    return ToolConfigDocument(
      localExec: LocalExecToolConfig.fromMap(
        jsonObject(decoded['local-exec'] ?? decoded['local_exec']),
      ),
      mcp: McpToolConfig.fromMap(jsonObject(decoded['mcp'])),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ToolConfigDocument copyWith({
    LocalExecToolConfig? localExec,
    McpToolConfig? mcp,
    Map<String, dynamic>? extra,
  }) {
    return ToolConfigDocument(
      localExec: localExec ?? this.localExec,
      mcp: mcp ?? this.mcp,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the config document as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'local-exec': localExec.toJson(),
      'mcp': mcp.toJson(),
    };
  }

  /// Encodes the config document as readable YAML.
  String toYaml() {
    return encodeYamlMap(toJson());
  }
}

/// LocalExecToolConfig describes configured local command execution tools.
class LocalExecToolConfig {
  /// Creates local execution tool settings.
  const LocalExecToolConfig({
    required this.enabled,
    required this.defaultTimeout,
    required this.defaultMaxOutputBytes,
    required this.allowedWorkdirs,
    required this.commands,
    this.extra = const <String, dynamic>{},
  });

  /// Whether local command aliases are exposed through the command MCP service.
  final bool enabled;

  /// Default Go-style duration for command execution.
  final String defaultTimeout;

  /// Default captured output limit in bytes.
  final int defaultMaxOutputBytes;

  /// Workspace roots where commands may run.
  final List<String> allowedWorkdirs;

  /// Allowlisted command aliases exposed through command templates.
  final List<LocalExecCommandConfig> commands;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses local-exec settings from decoded YAML.
  factory LocalExecToolConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('enabled')
      ..remove('default-timeout')
      ..remove('default_timeout')
      ..remove('default-max-output-bytes')
      ..remove('default_max_output_bytes')
      ..remove('allowed-workdirs')
      ..remove('allowed_workdirs')
      ..remove('commands');
    return LocalExecToolConfig(
      enabled: boolValue(map['enabled']),
      defaultTimeout: stringValue(
        map['default-timeout'] ?? map['default_timeout'],
        trim: true,
      ),
      defaultMaxOutputBytes: intValue(
        map['default-max-output-bytes'] ?? map['default_max_output_bytes'],
      ),
      allowedWorkdirs: stringList(
        map['allowed-workdirs'] ?? map['allowed_workdirs'],
        trim: true,
      ),
      commands: jsonObjectList(
        map['commands'],
      ).map(LocalExecCommandConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecToolConfig copyWith({
    bool? enabled,
    String? defaultTimeout,
    int? defaultMaxOutputBytes,
    List<String>? allowedWorkdirs,
    List<LocalExecCommandConfig>? commands,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecToolConfig(
      enabled: enabled ?? this.enabled,
      defaultTimeout: defaultTimeout ?? this.defaultTimeout,
      defaultMaxOutputBytes:
          defaultMaxOutputBytes ?? this.defaultMaxOutputBytes,
      allowedWorkdirs: allowedWorkdirs ?? this.allowedWorkdirs,
      commands: commands ?? this.commands,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes local-exec settings as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'enabled': enabled,
      if (defaultTimeout.isNotEmpty) 'default-timeout': defaultTimeout,
      if (defaultMaxOutputBytes != 0)
        'default-max-output-bytes': defaultMaxOutputBytes,
      if (allowedWorkdirs.isNotEmpty) 'allowed-workdirs': allowedWorkdirs,
      if (commands.isNotEmpty)
        'commands': commands.map((command) => command.toJson()).toList(),
    };
  }
}

/// LocalExecCommandConfig describes one allowlisted local command alias.
class LocalExecCommandConfig {
  /// Creates a local command alias config.
  const LocalExecCommandConfig({
    required this.name,
    required this.executable,
    required this.description,
    required this.args,
    required this.timeout,
    required this.maxOutputBytes,
    this.extra = const <String, dynamic>{},
  });

  /// Alias used to create the command template.
  final String name;

  /// Executable command run by the harness.
  final String executable;

  /// Model-facing description of the command.
  final String description;

  /// Static executable arguments.
  final List<String> args;

  /// Optional Go-style command timeout.
  final String timeout;

  /// Optional command-specific output limit.
  final int maxOutputBytes;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one local command from decoded YAML.
  factory LocalExecCommandConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('name')
      ..remove('executable')
      ..remove('description')
      ..remove('args')
      ..remove('timeout')
      ..remove('max-output-bytes')
      ..remove('max_output_bytes');
    return LocalExecCommandConfig(
      name: stringValue(map['name'], trim: true),
      executable: stringValue(map['executable'], trim: true),
      description: stringValue(map['description'], trim: true),
      args: stringList(map['args'], trim: true),
      timeout: stringValue(map['timeout'], trim: true),
      maxOutputBytes: intValue(
        map['max-output-bytes'] ?? map['max_output_bytes'],
      ),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecCommandConfig copyWith({
    String? name,
    String? executable,
    String? description,
    List<String>? args,
    String? timeout,
    int? maxOutputBytes,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecCommandConfig(
      name: name ?? this.name,
      executable: executable ?? this.executable,
      description: description ?? this.description,
      args: args ?? this.args,
      timeout: timeout ?? this.timeout,
      maxOutputBytes: maxOutputBytes ?? this.maxOutputBytes,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the command as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      'executable': executable,
      'description': description,
      if (args.isNotEmpty) 'args': args,
      if (timeout.isNotEmpty) 'timeout': timeout,
      if (maxOutputBytes != 0) 'max-output-bytes': maxOutputBytes,
    };
  }
}

/// McpToolConfig describes configured MCP toolsets.
class McpToolConfig {
  /// Creates MCP toolset settings.
  const McpToolConfig({
    required this.enabled,
    required this.servers,
    this.extra = const <String, dynamic>{},
  });

  /// Whether MCP toolsets are installed on the agent.
  final bool enabled;

  /// MCP servers exposed as runtime toolsets.
  final List<McpServerToolConfig> servers;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses MCP settings from decoded YAML.
  factory McpToolConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('enabled')
      ..remove('servers');
    return McpToolConfig(
      enabled: boolValue(map['enabled']),
      servers: jsonObjectList(
        map['servers'],
      ).map(McpServerToolConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  McpToolConfig copyWith({
    bool? enabled,
    List<McpServerToolConfig>? servers,
    Map<String, dynamic>? extra,
  }) {
    return McpToolConfig(
      enabled: enabled ?? this.enabled,
      servers: servers ?? this.servers,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes MCP settings as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'enabled': enabled,
      if (servers.isNotEmpty)
        'servers': servers.map((server) => server.toJson()).toList(),
    };
  }
}

/// McpServerToolConfig describes one MCP server connection.
class McpServerToolConfig {
  /// Creates an MCP server config.
  const McpServerToolConfig({
    required this.name,
    required this.transport,
    required this.command,
    required this.args,
    required this.env,
    required this.headersFromEnv,
    required this.endpoint,
    required this.url,
    required this.requireConfirmation,
    required this.requireConfirmationTools,
    required this.tools,
    this.extra = const <String, dynamic>{},
  });

  /// MCP server name used for diagnostics.
  final String name;

  /// Transport name, such as streamable-http or stdio.
  final String transport;

  /// Stdio server executable.
  final String command;

  /// Stdio server arguments.
  final List<String> args;

  /// Stdio server environment variables.
  final Map<String, String> env;

  /// HTTP headers resolved from environment variables for this MCP server.
  final Map<String, String> headersFromEnv;

  /// Preferred streamable HTTP endpoint.
  final String endpoint;

  /// Legacy HTTP URL field accepted by the harness.
  final String url;

  /// Whether all server tools require confirmation.
  final bool requireConfirmation;

  /// Specific server tool names that require confirmation.
  final List<String> requireConfirmationTools;

  /// Tool allowlist settings.
  final McpToolFilterConfig tools;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one MCP server from decoded YAML.
  factory McpServerToolConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('name')
      ..remove('transport')
      ..remove('command')
      ..remove('args')
      ..remove('env')
      ..remove('headers-from-env')
      ..remove('headers_from_env')
      ..remove('endpoint')
      ..remove('url')
      ..remove('require-confirmation')
      ..remove('require_confirmation')
      ..remove('require-confirmation-tools')
      ..remove('require_confirmation_tools')
      ..remove('tools');
    return McpServerToolConfig(
      name: stringValue(map['name'], trim: true),
      transport: stringValue(
        map['transport'],
        fallback: 'streamable-http',
        trim: true,
      ),
      command: stringValue(map['command'], trim: true),
      args: stringList(map['args'], trim: true),
      env: _stringMap(map['env']),
      headersFromEnv: _stringMap(
        map['headers-from-env'] ?? map['headers_from_env'],
      ),
      endpoint: stringValue(map['endpoint'], trim: true),
      url: stringValue(map['url'], trim: true),
      requireConfirmation: boolValue(
        map['require-confirmation'] ?? map['require_confirmation'],
      ),
      requireConfirmationTools: stringList(
        map['require-confirmation-tools'] ?? map['require_confirmation_tools'],
        trim: true,
      ),
      tools: McpToolFilterConfig.fromMap(jsonObject(map['tools'])),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  McpServerToolConfig copyWith({
    String? name,
    String? transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    Map<String, String>? headersFromEnv,
    String? endpoint,
    String? url,
    bool? requireConfirmation,
    List<String>? requireConfirmationTools,
    McpToolFilterConfig? tools,
    Map<String, dynamic>? extra,
  }) {
    return McpServerToolConfig(
      name: name ?? this.name,
      transport: transport ?? this.transport,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      headersFromEnv: headersFromEnv ?? this.headersFromEnv,
      endpoint: endpoint ?? this.endpoint,
      url: url ?? this.url,
      requireConfirmation: requireConfirmation ?? this.requireConfirmation,
      requireConfirmationTools:
          requireConfirmationTools ?? this.requireConfirmationTools,
      tools: tools ?? this.tools,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the MCP server as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      'transport': transport,
      if (command.isNotEmpty) 'command': command,
      if (args.isNotEmpty) 'args': args,
      if (env.isNotEmpty) 'env': env,
      if (headersFromEnv.isNotEmpty) 'headers-from-env': headersFromEnv,
      if (endpoint.isNotEmpty) 'endpoint': endpoint,
      if (url.isNotEmpty) 'url': url,
      if (requireConfirmation) 'require-confirmation': requireConfirmation,
      if (requireConfirmationTools.isNotEmpty)
        'require-confirmation-tools': requireConfirmationTools,
      if (tools.allow.isNotEmpty) 'tools': tools.toJson(),
    };
  }
}

/// McpToolFilterConfig describes MCP tool allowlist values.
class McpToolFilterConfig {
  /// Creates an MCP tool filter config.
  const McpToolFilterConfig({
    required this.allow,
    this.extra = const <String, dynamic>{},
  });

  /// Tool names allowed from this server.
  final List<String> allow;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses an MCP tool filter from decoded YAML.
  factory McpToolFilterConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)..remove('allow');
    return McpToolFilterConfig(
      allow: stringList(map['allow'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  McpToolFilterConfig copyWith({
    List<String>? allow,
    Map<String, dynamic>? extra,
  }) {
    return McpToolFilterConfig(
      allow: allow ?? this.allow,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the MCP tool filter as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{...extra, if (allow.isNotEmpty) 'allow': allow};
  }
}

/// Returns an empty tool config document.
ToolConfigDocument emptyToolConfigDocument() {
  return const ToolConfigDocument(
    localExec: LocalExecToolConfig(
      enabled: false,
      defaultTimeout: '',
      defaultMaxOutputBytes: 0,
      allowedWorkdirs: <String>[],
      commands: <LocalExecCommandConfig>[],
    ),
    mcp: McpToolConfig(enabled: false, servers: <McpServerToolConfig>[]),
  );
}

/// Creates a configured-command local execution entry.
LocalExecCommandConfig newLocalExecCommandConfig({
  required String name,
  required String executable,
  required String description,
}) {
  return LocalExecCommandConfig(
    name: name,
    executable: executable,
    description: description,
    args: const <String>[],
    timeout: '',
    maxOutputBytes: 0,
  );
}

/// Creates a streamable HTTP MCP server entry.
McpServerToolConfig newHttpMcpServerToolConfig({
  required String name,
  required String endpoint,
  Map<String, String> headersFromEnv = const <String, String>{},
}) {
  return McpServerToolConfig(
    name: name,
    transport: 'streamable-http',
    command: '',
    args: const <String>[],
    env: const <String, String>{},
    headersFromEnv: headersFromEnv,
    endpoint: endpoint,
    url: '',
    requireConfirmation: false,
    requireConfirmationTools: const <String>[],
    tools: const McpToolFilterConfig(allow: <String>[]),
  );
}

/// Creates target-state tool config for configured memory domains.
ToolConfigDocument graphBackedMemoryToolConfigForDomains({
  required List<McpServerRuntime> memoryDomains,
  required AgentMemoryRuntime agentMemory,
  WorkflowRuntime? workflow,
  required LocalExecToolConfig localExec,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) {
  final defaultDomain = memoryDomains.firstWhere(
    (domain) => domain.id == agentMemory.defaultWriteDomain,
  );
  final singleDomain =
      agentMemory.readDomains.length == 1 &&
      agentMemory.writeDomains.length == 1 &&
      agentMemory.defaultWriteDomain == agentMemory.readDomains.single &&
      agentMemory.defaultWriteDomain == agentMemory.writeDomains.single;
  return ToolConfigDocument(
    localExec: localExec,
    mcp: McpToolConfig(
      enabled: true,
      servers: <McpServerToolConfig>[
        newHttpMcpServerToolConfig(
          name: _domainToolServerName(defaultDomain.id),
          endpoint: defaultDomain.endpoint,
        ).copyWith(
          requireConfirmationTools: singleDomain
              ? graphBackedMcpConfirmationToolNames
              : const <String>[],
          tools: McpToolFilterConfig(
            allow: singleDomain
                ? graphBackedMcpToolNames
                : graphBackedMcpReadOnlyToolNames,
          ),
        ),
        if (workflow != null && workflow.enabled)
          newHttpMcpServerToolConfig(
            name: 'workflow',
            endpoint: _workflowMcpUrl(workflow),
          ).copyWith(
            tools: const McpToolFilterConfig(allow: workflowMcpToolNames),
          ),
      ],
    ),
    extra: <String, dynamic>{
      ...extra,
      'memory': <String, dynamic>{
        'actor': agentMemory.actor,
        'read-domains': <Map<String, dynamic>>[
          for (final domain in memoryDomains)
            if (agentMemory.readDomains.contains(domain.id))
              _memoryDomainToolJson(domain),
        ],
        'write-domains': agentMemory.writeDomains,
        'default-write-domain': agentMemory.defaultWriteDomain,
        'allowed-sensitivities': agentMemory.allowedSensitivities,
        if (agentMemory.allowedFlows.isNotEmpty)
          'allowed-flows': <Map<String, dynamic>>[
            for (final flow in agentMemory.allowedFlows) flow.toJson(),
          ],
      },
    },
  );
}

/// Returns the workflow MCP endpoint beside the workflow REST API.
String _workflowMcpUrl(WorkflowRuntime workflow) {
  final uri = Uri.parse(workflow.apiBaseUrl);
  return uri.replace(path: '/mcp', query: null).toString();
}

/// Encodes one memory domain for harness-owned memory access.
Map<String, dynamic> _memoryDomainToolJson(McpServerRuntime domain) {
  return <String, dynamic>{
    'id': domain.id,
    'label': domain.label,
    'endpoint': domain.endpoint,
  };
}

/// Returns the stable MCP server name for one domain-backed toolset.
String _domainToolServerName(String domainId) {
  return 'memory_${domainId.replaceAll('-', '_')}';
}

/// Creates a stdio MCP server entry.
McpServerToolConfig newStdioMcpServerToolConfig({
  required String name,
  required String command,
}) {
  return McpServerToolConfig(
    name: name,
    transport: 'stdio',
    command: command,
    args: const <String>[],
    env: const <String, String>{},
    headersFromEnv: const <String, String>{},
    endpoint: '',
    url: '',
    requireConfirmation: false,
    requireConfirmationTools: const <String>[],
    tools: const McpToolFilterConfig(allow: <String>[]),
  );
}

/// Returns a validation error for invalid tool config state.
String toolConfigValidationError(ToolConfigDocument document) {
  final localError = _localExecValidationError(document.localExec);
  if (localError.isNotEmpty) {
    return localError;
  }
  return _mcpValidationError(document.mcp);
}

/// Returns a validation error for local-exec settings.
String _localExecValidationError(LocalExecToolConfig config) {
  if (!config.enabled) {
    return '';
  }
  if (config.defaultTimeout.trim().isNotEmpty &&
      !_isGoDuration(config.defaultTimeout)) {
    return 'local-exec default-timeout must be a Go duration';
  }
  if (config.defaultMaxOutputBytes < 0) {
    return 'local-exec default-max-output-bytes must not be negative';
  }
  if (config.allowedWorkdirs.any((value) => value.trim().isEmpty)) {
    return 'local-exec allowed-workdirs must not contain empty paths';
  }
  if (config.commands.isEmpty) {
    return 'local-exec commands must not be empty when enabled';
  }
  final names = <String>{};
  for (final command in config.commands) {
    final name = command.name.trim();
    if (name.isEmpty) {
      return 'local-exec command name must not be empty';
    }
    if (!_toolNamePattern.hasMatch(name)) {
      return 'local-exec command "$name" uses an invalid name';
    }
    if (!names.add(name)) {
      return 'local-exec duplicate command "$name"';
    }
    final error = _localExecCommandValidationError(command);
    if (error.isNotEmpty) {
      return error;
    }
  }
  return '';
}

/// Returns a validation error for one local command.
String _localExecCommandValidationError(LocalExecCommandConfig command) {
  final name = command.name.trim();
  if (command.executable.trim().isEmpty) {
    return 'local-exec command "$name" executable must not be empty';
  }
  if (command.description.trim().isEmpty) {
    return 'local-exec command "$name" description must not be empty';
  }
  if (command.timeout.trim().isNotEmpty && !_isGoDuration(command.timeout)) {
    return 'local-exec command "$name" timeout must be a Go duration';
  }
  if (command.maxOutputBytes < 0) {
    return 'local-exec command "$name" max-output-bytes must not be negative';
  }
  return '';
}

/// Returns a validation error for MCP settings.
String _mcpValidationError(McpToolConfig config) {
  if (!config.enabled) {
    return '';
  }
  if (config.servers.isEmpty) {
    return 'mcp servers must not be empty when enabled';
  }
  final names = <String>{};
  for (final server in config.servers) {
    final name = server.name.trim();
    if (name.isEmpty) {
      return 'mcp server name must not be empty';
    }
    if (!_toolNamePattern.hasMatch(name)) {
      return 'mcp server "$name" uses an invalid name';
    }
    if (!names.add(name)) {
      return 'mcp duplicate server "$name"';
    }
    final error = _mcpServerValidationError(server);
    if (error.isNotEmpty) {
      return error;
    }
  }
  return '';
}

/// Returns a validation error for one MCP server.
String _mcpServerValidationError(McpServerToolConfig server) {
  final name = server.name.trim();
  final transport = normalizedMcpTransport(server.transport);
  switch (transport) {
    case 'stdio':
      if (server.command.trim().isEmpty) {
        return 'mcp server "$name" command must not be empty for stdio';
      }
      if (server.endpoint.trim().isNotEmpty || server.url.trim().isNotEmpty) {
        return 'mcp server "$name" endpoint is only valid for HTTP transport';
      }
      final filesystemError = _filesystemRootValidationError(server);
      if (filesystemError.isNotEmpty) {
        return filesystemError;
      }
    case 'streamable-http':
      if (server.command.trim().isNotEmpty || server.args.isNotEmpty) {
        return 'mcp server "$name" command is only valid for stdio transport';
      }
      final endpoint = mcpServerEndpoint(server);
      if (endpoint.isEmpty) {
        return 'mcp server "$name" endpoint must not be empty';
      }
      final uri = Uri.tryParse(endpoint);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        return 'mcp server "$name" endpoint must be an absolute HTTP URL';
      }
    default:
      return 'mcp server "$name" transport must be stdio or streamable-http';
  }
  if (server.requireConfirmation &&
      server.requireConfirmationTools.isNotEmpty) {
    return 'mcp server "$name" cannot combine all-tool and named-tool confirmation';
  }
  final allowError = _uniqueStringValidationError(
    'mcp server $name tools allow',
    server.tools.allow,
  );
  if (allowError.isNotEmpty) {
    return allowError;
  }
  final confirmationError = _uniqueStringValidationError(
    'mcp server $name require-confirmation-tools',
    server.requireConfirmationTools,
  );
  if (confirmationError.isNotEmpty) {
    return confirmationError;
  }
  if (server.env.keys.any((key) => key.trim().isEmpty)) {
    return 'mcp server "$name" env must not contain empty variable names';
  }
  if (server.headersFromEnv.keys.any((key) => key.trim().isEmpty)) {
    return 'mcp server "$name" headers-from-env must not contain empty header names';
  }
  return '';
}

/// Returns a validation error for filesystem MCP server roots.
String _filesystemRootValidationError(McpServerToolConfig server) {
  if (!_isFilesystemMcpServer(server)) {
    return '';
  }
  final roots = _filesystemRootArgs(server);
  if (roots.isEmpty) {
    return 'mcp filesystem server "${server.name}" needs one absolute root path';
  }
  for (final root in roots) {
    if (!_looksAbsolutePath(root)) {
      return 'mcp filesystem server "${server.name}" root path "$root" must be absolute';
    }
  }
  return '';
}

/// Returns a validation error when a string list has empty or duplicate values.
String _uniqueStringValidationError(String label, List<String> values) {
  final seen = <String>{};
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '$label must not contain empty values';
    }
    if (!seen.add(trimmed)) {
      return '$label contains duplicate value "$trimmed"';
    }
  }
  return '';
}

/// Returns the normalized MCP transport value used by the harness.
String normalizedMcpTransport(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'http') {
    return 'streamable-http';
  }
  return normalized;
}

/// Returns the preferred HTTP endpoint field for an MCP server.
String mcpServerEndpoint(McpServerToolConfig server) {
  final endpoint = server.endpoint.trim();
  if (endpoint.isNotEmpty) {
    return endpoint;
  }
  return server.url.trim();
}

/// Converts a decoded map to a trimmed string map.
Map<String, String> _stringMap(dynamic value) {
  if (value is! Map<String, dynamic>) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries)
      entry.key.trim(): entry.value.toString().trim(),
  }..removeWhere((key, value) => key.isEmpty || value.isEmpty);
}

/// Reports whether a value looks like a Go duration.
bool _isGoDuration(String value) {
  return _goDurationPattern.hasMatch(value.trim());
}

/// Reports whether a stdio server appears to be the filesystem MCP server.
bool _isFilesystemMcpServer(McpServerToolConfig server) {
  if (server.command.toLowerCase().contains('filesystem')) {
    return true;
  }
  return server.args.any((arg) {
    return arg.toLowerCase().contains('server-filesystem');
  });
}

/// Extracts filesystem root arguments from server args.
List<String> _filesystemRootArgs(McpServerToolConfig server) {
  final roots = <String>[];
  var collect = server.command.toLowerCase().contains('filesystem');
  for (final arg in server.args) {
    final trimmed = arg.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (trimmed.toLowerCase().contains('server-filesystem')) {
      collect = true;
      continue;
    }
    if (collect && !trimmed.startsWith('-')) {
      roots.add(trimmed);
    }
  }
  return roots;
}

/// Reports whether a path is absolute on Unix or Windows.
bool _looksAbsolutePath(String value) {
  final path = value.trim();
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

final RegExp _toolNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');
final RegExp _goDurationPattern = RegExp(
  r'^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$',
);
