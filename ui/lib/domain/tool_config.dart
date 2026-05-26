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

/// Source-control MCP tools exposed by the sourcecontrol service.
const List<String> sourceControlMcpToolNames = <String>[
  'sourcecontrol.prepare_worktree',
  'sourcecontrol.status',
  'sourcecontrol.commit',
  'sourcecontrol.push',
  'sourcecontrol.open_pull_request',
  'sourcecontrol.backup',
  'sourcecontrol.restore',
  'sourcecontrol.cleanup_worktree',
];

/// ToolConfigDocument represents one harness tool config YAML file.
class ToolConfigDocument {
  /// Creates a tool config document.
  const ToolConfigDocument({
    required this.localExec,
    required this.mcp,
    this.nodePresets = const <NodePresetConfig>[],
    this.validations = const <ToolValidationConfig>[],
    this.extra = const <String, dynamic>{},
  });

  /// Local OS command tool settings.
  final LocalExecToolConfig localExec;

  /// MCP toolset settings.
  final McpToolConfig mcp;

  /// Installed workflow node presets backed by generic tool boundaries.
  final List<NodePresetConfig> nodePresets;

  /// Portable tool-package validations for agent and workflow behavior.
  final List<ToolValidationConfig> validations;

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
      ..remove('mcp')
      ..remove('node-presets')
      ..remove('validations');
    return ToolConfigDocument(
      localExec: LocalExecToolConfig.fromMap(
        jsonObject(decoded['local-exec'] ?? decoded['local_exec']),
      ),
      mcp: McpToolConfig.fromMap(jsonObject(decoded['mcp'])),
      nodePresets: jsonObjectList(
        decoded['node-presets'],
      ).map(NodePresetConfig.fromMap).toList(),
      validations: jsonObjectList(
        decoded['validations'],
      ).map(ToolValidationConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ToolConfigDocument copyWith({
    LocalExecToolConfig? localExec,
    McpToolConfig? mcp,
    List<NodePresetConfig>? nodePresets,
    List<ToolValidationConfig>? validations,
    Map<String, dynamic>? extra,
  }) {
    return ToolConfigDocument(
      localExec: localExec ?? this.localExec,
      mcp: mcp ?? this.mcp,
      nodePresets: nodePresets ?? this.nodePresets,
      validations: validations ?? this.validations,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the config document as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'local-exec': localExec.toJson(),
      'mcp': mcp.toJson(),
      if (nodePresets.isNotEmpty)
        'node-presets': nodePresets.map((preset) => preset.toJson()).toList(),
      if (validations.isNotEmpty)
        'validations': validations
            .map((validation) => validation.toJson())
            .toList(),
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
    required this.commands,
    this.extra = const <String, dynamic>{},
  });

  /// Whether local CLI surfaces are exposed through the command MCP service.
  final bool enabled;

  /// Default Go-style duration for command execution.
  final String defaultTimeout;

  /// Default captured output limit in bytes.
  final int defaultMaxOutputBytes;

  /// Allowlisted CLI command surfaces exposed through command templates.
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
    List<LocalExecCommandConfig>? commands,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecToolConfig(
      enabled: enabled ?? this.enabled,
      defaultTimeout: defaultTimeout ?? this.defaultTimeout,
      defaultMaxOutputBytes:
          defaultMaxOutputBytes ?? this.defaultMaxOutputBytes,
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
      if (commands.isNotEmpty)
        'commands': commands.map((command) => command.toJson()).toList(),
    };
  }
}

/// LocalExecCommandConfig describes one documented local CLI surface.
class LocalExecCommandConfig {
  /// Creates a local command config.
  const LocalExecCommandConfig({
    required this.name,
    required this.executable,
    required this.description,
    required this.args,
    required this.timeout,
    required this.maxOutputBytes,
    required this.installation,
    required this.surface,
    required this.operations,
    this.extra = const <String, dynamic>{},
  });

  /// CLI tool name used to create the command template.
  final String name;

  /// Executable command run by the harness.
  final String executable;

  /// Model-facing description of the CLI.
  final String description;

  /// Optional advanced executable argument template when no operations are used.
  final List<String> args;

  /// Optional Go-style command timeout.
  final String timeout;

  /// Optional command-specific output limit.
  final int maxOutputBytes;

  /// Last recorded executable availability check for live validation.
  final LocalExecInstallationConfig installation;

  /// Model-facing documentation for supported subcommands and flags.
  final LocalExecCommandSurfaceConfig surface;

  /// Deterministic workflow-callable operations for this executable.
  final List<LocalExecOperationConfig> operations;

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
      ..remove('max_output_bytes')
      ..remove('installation')
      ..remove('install-check')
      ..remove('install_check')
      ..remove('surface')
      ..remove('operations');
    return LocalExecCommandConfig(
      name: stringValue(map['name'], trim: true),
      executable: stringValue(map['executable'], trim: true),
      description: stringValue(map['description'], trim: true),
      args: stringList(map['args'], trim: true),
      timeout: stringValue(map['timeout'], trim: true),
      maxOutputBytes: intValue(
        map['max-output-bytes'] ?? map['max_output_bytes'],
      ),
      installation: LocalExecInstallationConfig.fromMap(
        jsonObject(
          map['installation'] ?? map['install-check'] ?? map['install_check'],
        ),
      ),
      surface: LocalExecCommandSurfaceConfig.fromMap(
        jsonObject(map['surface']),
      ),
      operations: jsonObjectList(
        map['operations'],
      ).map(LocalExecOperationConfig.fromMap).toList(),
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
    LocalExecInstallationConfig? installation,
    LocalExecCommandSurfaceConfig? surface,
    List<LocalExecOperationConfig>? operations,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecCommandConfig(
      name: name ?? this.name,
      executable: executable ?? this.executable,
      description: description ?? this.description,
      args: args ?? this.args,
      timeout: timeout ?? this.timeout,
      maxOutputBytes: maxOutputBytes ?? this.maxOutputBytes,
      installation: installation ?? this.installation,
      surface: surface ?? this.surface,
      operations: operations ?? this.operations,
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
      if (!installation.isEmpty) 'installation': installation.toJson(),
      if (!surface.isEmpty) 'surface': surface.toJson(),
      if (operations.isNotEmpty)
        'operations': operations
            .map((operation) => operation.toJson())
            .toList(),
    };
  }
}

/// LocalExecInstallationConfig stores a recorded executable availability check.
class LocalExecInstallationConfig {
  /// Creates an immutable install verification record.
  const LocalExecInstallationConfig({
    required this.verified,
    required this.checkedAt,
    required this.executable,
    required this.path,
    required this.version,
    required this.error,
    this.extra = const <String, dynamic>{},
  });

  /// Whether the executable was found and can be used for live validation.
  final bool verified;

  /// UTC timestamp for the latest check.
  final String checkedAt;

  /// Executable name that was checked.
  final String executable;

  /// Resolved executable path, when known.
  final String path;

  /// First reported version line, when available.
  final String version;

  /// Failure detail from the latest check.
  final String error;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Reports whether no install check has been recorded.
  bool get isEmpty =>
      !verified &&
      checkedAt.isEmpty &&
      executable.isEmpty &&
      path.isEmpty &&
      version.isEmpty &&
      error.isEmpty &&
      extra.isEmpty;

  /// Parses one install verification record from decoded YAML.
  factory LocalExecInstallationConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('verified')
      ..remove('checked-at')
      ..remove('checked_at')
      ..remove('executable')
      ..remove('path')
      ..remove('version')
      ..remove('error');
    return LocalExecInstallationConfig(
      verified: boolValue(map['verified']),
      checkedAt: stringValue(
        map['checked-at'] ?? map['checked_at'],
        trim: true,
      ),
      executable: stringValue(map['executable'], trim: true),
      path: stringValue(map['path'], trim: true),
      version: stringValue(map['version'], trim: true),
      error: stringValue(map['error'], trim: true),
      extra: extra,
    );
  }

  /// Encodes this verification record as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'verified': verified,
      if (checkedAt.isNotEmpty) 'checked-at': checkedAt,
      if (executable.isNotEmpty) 'executable': executable,
      if (path.isNotEmpty) 'path': path,
      if (version.isNotEmpty) 'version': version,
      if (error.isNotEmpty) 'error': error,
    };
  }
}

/// LocalExecOperationConfig describes one workflow-callable CLI operation.
class LocalExecOperationConfig {
  /// Creates a deterministic local CLI operation.
  const LocalExecOperationConfig({
    required this.name,
    required this.description,
    required this.args,
    required this.inputSchema,
    required this.output,
    required this.outputSchema,
    required this.timeout,
    required this.maxOutputBytes,
    this.extra = const <String, dynamic>{},
  });

  /// Operation name combined with the command name for workflow template ids.
  final String name;

  /// Human-readable operation purpose.
  final String description;

  /// Argument template tokens rendered by the command service.
  final List<String> args;

  /// Optional JSON-schema-like parameter contract.
  final Map<String, dynamic> inputSchema;

  /// Raw output parsing contract.
  final LocalExecOperationOutputConfig output;

  /// Optional JSON-schema-like output validation contract.
  final Map<String, dynamic> outputSchema;

  /// Optional Go-style operation timeout.
  final String timeout;

  /// Optional operation-specific output capture limit.
  final int maxOutputBytes;

  /// Fields preserved outside the known operation schema.
  final Map<String, dynamic> extra;

  /// Parses one deterministic operation from decoded YAML.
  factory LocalExecOperationConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('name')
      ..remove('description')
      ..remove('args')
      ..remove('input-schema')
      ..remove('input_schema')
      ..remove('output')
      ..remove('output-schema')
      ..remove('output_schema')
      ..remove('timeout')
      ..remove('max-output-bytes')
      ..remove('max_output_bytes');
    return LocalExecOperationConfig(
      name: stringValue(map['name'], trim: true),
      description: stringValue(map['description'], trim: true),
      args: stringList(map['args'], trim: true),
      inputSchema: jsonObject(map['input-schema'] ?? map['input_schema']),
      output: LocalExecOperationOutputConfig.fromMap(jsonObject(map['output'])),
      outputSchema: jsonObject(map['output-schema'] ?? map['output_schema']),
      timeout: stringValue(map['timeout'], trim: true),
      maxOutputBytes: intValue(
        map['max-output-bytes'] ?? map['max_output_bytes'],
      ),
      extra: extra,
    );
  }

  /// Returns a copy with selected operation values changed.
  LocalExecOperationConfig copyWith({
    String? name,
    String? description,
    List<String>? args,
    Map<String, dynamic>? inputSchema,
    LocalExecOperationOutputConfig? output,
    Map<String, dynamic>? outputSchema,
    String? timeout,
    int? maxOutputBytes,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecOperationConfig(
      name: name ?? this.name,
      description: description ?? this.description,
      args: args ?? this.args,
      inputSchema: inputSchema ?? this.inputSchema,
      output: output ?? this.output,
      outputSchema: outputSchema ?? this.outputSchema,
      timeout: timeout ?? this.timeout,
      maxOutputBytes: maxOutputBytes ?? this.maxOutputBytes,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes the operation as JSON-compatible config data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      'description': description,
      if (args.isNotEmpty) 'args': args,
      if (inputSchema.isNotEmpty) 'input-schema': inputSchema,
      if (!output.isEmpty) 'output': output.toJson(),
      if (outputSchema.isNotEmpty) 'output-schema': outputSchema,
      if (timeout.isNotEmpty) 'timeout': timeout,
      if (maxOutputBytes != 0) 'max-output-bytes': maxOutputBytes,
    };
  }
}

/// LocalExecOperationOutputConfig describes operation output parsing.
class LocalExecOperationOutputConfig {
  /// Creates output parsing metadata.
  const LocalExecOperationOutputConfig({
    required this.format,
    required this.source,
    this.extra = const <String, dynamic>{},
  });

  /// Output format, such as text or json.
  final String format;

  /// Output stream, such as stdout, stderr, or combined.
  final String source;

  /// Fields preserved outside the known output schema.
  final Map<String, dynamic> extra;

  /// Whether no output parsing metadata is configured.
  bool get isEmpty => format.isEmpty && source.isEmpty && extra.isEmpty;

  /// Parses output metadata from decoded YAML.
  factory LocalExecOperationOutputConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('format')
      ..remove('source');
    return LocalExecOperationOutputConfig(
      format: stringValue(map['format'], trim: true),
      source: stringValue(map['source'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected output values changed.
  LocalExecOperationOutputConfig copyWith({
    String? format,
    String? source,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecOperationOutputConfig(
      format: format ?? this.format,
      source: source ?? this.source,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes output metadata as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      if (format.isNotEmpty) 'format': format,
      if (source.isNotEmpty) 'source': source,
    };
  }
}

/// LocalExecCommandSurfaceConfig documents one CLI surface for model use.
class LocalExecCommandSurfaceConfig {
  /// Creates CLI surface metadata.
  const LocalExecCommandSurfaceConfig({
    required this.globalFlags,
    required this.subcommands,
    this.extra = const <String, dynamic>{},
  });

  /// Flags accepted before or across subcommands.
  final List<LocalExecCommandFlagConfig> globalFlags;

  /// Documented subcommands exposed by this CLI.
  final List<LocalExecSubcommandConfig> subcommands;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Whether this surface contains no model-facing metadata.
  bool get isEmpty =>
      globalFlags.isEmpty && subcommands.isEmpty && extra.isEmpty;

  /// Parses CLI surface metadata from decoded YAML.
  factory LocalExecCommandSurfaceConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('global-flags')
      ..remove('global_flags')
      ..remove('subcommands');
    return LocalExecCommandSurfaceConfig(
      globalFlags: jsonObjectList(
        map['global-flags'] ?? map['global_flags'],
      ).map(LocalExecCommandFlagConfig.fromMap).toList(),
      subcommands: jsonObjectList(
        map['subcommands'],
      ).map(LocalExecSubcommandConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecCommandSurfaceConfig copyWith({
    List<LocalExecCommandFlagConfig>? globalFlags,
    List<LocalExecSubcommandConfig>? subcommands,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecCommandSurfaceConfig(
      globalFlags: globalFlags ?? this.globalFlags,
      subcommands: subcommands ?? this.subcommands,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes CLI surface metadata as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      if (globalFlags.isNotEmpty)
        'global-flags': globalFlags.map((flag) => flag.toJson()).toList(),
      if (subcommands.isNotEmpty)
        'subcommands': subcommands
            .map((subcommand) => subcommand.toJson())
            .toList(),
    };
  }
}

/// LocalExecCommandFlagConfig documents one CLI flag.
class LocalExecCommandFlagConfig {
  /// Creates CLI flag metadata.
  const LocalExecCommandFlagConfig({
    required this.name,
    required this.description,
    this.extra = const <String, dynamic>{},
  });

  /// Flag spelling, such as `--short` or `-C`.
  final String name;

  /// Model-facing flag description.
  final String description;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one CLI flag from decoded YAML.
  factory LocalExecCommandFlagConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('name')
      ..remove('description');
    return LocalExecCommandFlagConfig(
      name: stringValue(map['name'], trim: true),
      description: stringValue(map['description'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecCommandFlagConfig copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecCommandFlagConfig(
      name: name ?? this.name,
      description: description ?? this.description,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes CLI flag metadata as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      if (description.isNotEmpty) 'description': description,
    };
  }
}

/// LocalExecSubcommandConfig documents one CLI subcommand.
class LocalExecSubcommandConfig {
  /// Creates CLI subcommand metadata.
  const LocalExecSubcommandConfig({
    required this.name,
    required this.description,
    required this.flags,
    required this.subcommands,
    this.extra = const <String, dynamic>{},
  });

  /// Subcommand name, such as `status` or `log`.
  final String name;

  /// Model-facing subcommand description.
  final String description;

  /// Flags accepted by this subcommand.
  final List<LocalExecCommandFlagConfig> flags;

  /// Nested subcommands accepted after this subcommand token.
  final List<LocalExecSubcommandConfig> subcommands;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses one CLI subcommand from decoded YAML.
  factory LocalExecSubcommandConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('name')
      ..remove('description')
      ..remove('flags')
      ..remove('subcommands');
    return LocalExecSubcommandConfig(
      name: stringValue(map['name'], trim: true),
      description: stringValue(map['description'], trim: true),
      flags: jsonObjectList(
        map['flags'],
      ).map(LocalExecCommandFlagConfig.fromMap).toList(),
      subcommands: jsonObjectList(
        map['subcommands'],
      ).map(LocalExecSubcommandConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecSubcommandConfig copyWith({
    String? name,
    String? description,
    List<LocalExecCommandFlagConfig>? flags,
    List<LocalExecSubcommandConfig>? subcommands,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecSubcommandConfig(
      name: name ?? this.name,
      description: description ?? this.description,
      flags: flags ?? this.flags,
      subcommands: subcommands ?? this.subcommands,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes CLI subcommand metadata as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'name': name,
      if (description.isNotEmpty) 'description': description,
      if (flags.isNotEmpty)
        'flags': flags.map((flag) => flag.toJson()).toList(),
      if (subcommands.isNotEmpty)
        'subcommands': subcommands
            .map((subcommand) => subcommand.toJson())
            .toList(),
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

/// NodePresetConfig describes one reusable workflow node palette preset.
class NodePresetConfig {
  /// Creates node preset metadata.
  const NodePresetConfig({
    required this.id,
    required this.label,
    required this.surface,
    required this.action,
    required this.description,
    required this.arguments,
    required this.inputSchema,
    this.extra = const <String, dynamic>{},
  });

  /// Stable preset id used by workflow authoring palettes.
  final String id;

  /// Human-readable preset label.
  final String label;

  /// Owning workbench surface, such as command or mcp.
  final String surface;

  /// Generic workflow action this preset compiles to.
  final String action;

  /// Short explanation shown beside the preset.
  final String description;

  /// Default action arguments emitted when the preset is inserted.
  final Map<String, dynamic> arguments;

  /// Optional JSON-schema-like input envelope expected by the preset.
  final Map<String, dynamic> inputSchema;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses node preset metadata from decoded YAML.
  factory NodePresetConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('label')
      ..remove('surface')
      ..remove('action')
      ..remove('description')
      ..remove('arguments')
      ..remove('input-schema');
    return NodePresetConfig(
      id: stringValue(map['id'], trim: true),
      label: stringValue(map['label'], trim: true),
      surface: stringValue(map['surface'], trim: true),
      action: stringValue(map['action'], trim: true),
      description: stringValue(map['description'], trim: true),
      arguments: jsonObject(map['arguments']),
      inputSchema: jsonObject(map['input-schema']),
      extra: extra,
    );
  }

  /// Encodes this preset as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'id': id,
      'label': label,
      if (surface.isNotEmpty) 'surface': surface,
      'action': action,
      if (description.isNotEmpty) 'description': description,
      if (arguments.isNotEmpty) 'arguments': arguments,
      if (inputSchema.isNotEmpty) 'input-schema': inputSchema,
    };
  }
}

/// ToolValidationConfig describes one portable tool-package test case.
class ToolValidationConfig {
  /// Creates tool validation metadata.
  const ToolValidationConfig({
    required this.id,
    required this.label,
    required this.description,
    required this.mode,
    required this.target,
    required this.prompt,
    required this.input,
    required this.fixtures,
    required this.mocks,
    required this.expected,
    required this.assertions,
    this.extra = const <String, dynamic>{},
  });

  /// Stable validation id used by the validation runner.
  final String id;

  /// Human-readable validation label.
  final String label;

  /// Short validation purpose.
  final String description;

  /// Execution mode, usually mocked or live.
  final String mode;

  /// Invocation surface under test.
  final ToolValidationTargetConfig target;

  /// Prompt used when the target exercises agent tool selection.
  final String prompt;

  /// Input envelope supplied to the selected target.
  final Map<String, dynamic> input;

  /// Local fixture metadata, such as files or test servers.
  final Map<String, dynamic> fixtures;

  /// Fake command, MCP, or model responses keyed by boundary call.
  final Map<String, dynamic> mocks;

  /// Expected output, status, and diagnostics.
  final Map<String, dynamic> expected;

  /// Generic assertion records checked by the validation runner.
  final List<ToolValidationAssertionConfig> assertions;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses validation metadata from decoded YAML.
  factory ToolValidationConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('label')
      ..remove('description')
      ..remove('mode')
      ..remove('target')
      ..remove('prompt')
      ..remove('input')
      ..remove('fixtures')
      ..remove('mocks')
      ..remove('expected')
      ..remove('assertions');
    return ToolValidationConfig(
      id: stringValue(map['id'], trim: true),
      label: stringValue(map['label'], trim: true),
      description: stringValue(map['description'], trim: true),
      mode: stringValue(map['mode'], trim: true),
      target: ToolValidationTargetConfig.fromMap(jsonObject(map['target'])),
      prompt: stringValue(map['prompt'], trim: true),
      input: jsonObject(map['input']),
      fixtures: jsonObject(map['fixtures']),
      mocks: jsonObject(map['mocks']),
      expected: jsonObject(map['expected']),
      assertions: jsonObjectList(
        map['assertions'],
      ).map(ToolValidationAssertionConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ToolValidationConfig copyWith({
    String? id,
    String? label,
    String? description,
    String? mode,
    ToolValidationTargetConfig? target,
    String? prompt,
    Map<String, dynamic>? input,
    Map<String, dynamic>? fixtures,
    Map<String, dynamic>? mocks,
    Map<String, dynamic>? expected,
    List<ToolValidationAssertionConfig>? assertions,
    Map<String, dynamic>? extra,
  }) {
    return ToolValidationConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      mode: mode ?? this.mode,
      target: target ?? this.target,
      prompt: prompt ?? this.prompt,
      input: input ?? this.input,
      fixtures: fixtures ?? this.fixtures,
      mocks: mocks ?? this.mocks,
      expected: expected ?? this.expected,
      assertions: assertions ?? this.assertions,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes this validation as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'id': id,
      'label': label,
      if (description.isNotEmpty) 'description': description,
      if (mode.isNotEmpty) 'mode': mode,
      'target': target.toJson(),
      if (prompt.isNotEmpty) 'prompt': prompt,
      if (input.isNotEmpty) 'input': input,
      if (fixtures.isNotEmpty) 'fixtures': fixtures,
      if (mocks.isNotEmpty) 'mocks': mocks,
      if (expected.isNotEmpty) 'expected': expected,
      if (assertions.isNotEmpty)
        'assertions': assertions
            .map((assertion) => assertion.toJson())
            .toList(),
    };
  }
}

/// ToolValidationTargetConfig identifies the invocation surface under test.
class ToolValidationTargetConfig {
  /// Creates validation target metadata.
  const ToolValidationTargetConfig({
    required this.type,
    required this.presetId,
    required this.command,
    required this.operation,
    required this.mcpServer,
    required this.mcpTool,
    this.extra = const <String, dynamic>{},
  });

  /// Target type: command-operation, workflow-node, mcp-tool, or agent-tool-call.
  final String type;

  /// Workflow node preset id under test.
  final String presetId;

  /// Local command name under test.
  final String command;

  /// Deterministic command operation under test.
  final String operation;

  /// MCP server id under test.
  final String mcpServer;

  /// MCP tool name under test.
  final String mcpTool;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses validation target metadata from decoded YAML.
  factory ToolValidationTargetConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('type')
      ..remove('preset-id')
      ..remove('command')
      ..remove('operation')
      ..remove('mcp-server')
      ..remove('mcp-tool');
    return ToolValidationTargetConfig(
      type: stringValue(map['type'], trim: true),
      presetId: stringValue(map['preset-id'], trim: true),
      command: stringValue(map['command'], trim: true),
      operation: stringValue(map['operation'], trim: true),
      mcpServer: stringValue(map['mcp-server'], trim: true),
      mcpTool: stringValue(map['mcp-tool'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ToolValidationTargetConfig copyWith({
    String? type,
    String? presetId,
    String? command,
    String? operation,
    String? mcpServer,
    String? mcpTool,
    Map<String, dynamic>? extra,
  }) {
    return ToolValidationTargetConfig(
      type: type ?? this.type,
      presetId: presetId ?? this.presetId,
      command: command ?? this.command,
      operation: operation ?? this.operation,
      mcpServer: mcpServer ?? this.mcpServer,
      mcpTool: mcpTool ?? this.mcpTool,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes this target as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'type': type,
      if (presetId.isNotEmpty) 'preset-id': presetId,
      if (command.isNotEmpty) 'command': command,
      if (operation.isNotEmpty) 'operation': operation,
      if (mcpServer.isNotEmpty) 'mcp-server': mcpServer,
      if (mcpTool.isNotEmpty) 'mcp-tool': mcpTool,
    };
  }
}

/// ToolValidationAssertionConfig describes one expected validation result.
class ToolValidationAssertionConfig {
  /// Creates a validation assertion record.
  const ToolValidationAssertionConfig({
    required this.type,
    required this.path,
    required this.equals,
    required this.contains,
    required this.matches,
    required this.schema,
    required this.message,
    this.extra = const <String, dynamic>{},
  });

  /// Assertion type.
  final String type;

  /// Optional output path or JSON path to inspect.
  final String path;

  /// Expected exact value.
  final dynamic equals;

  /// Expected contained text.
  final String contains;

  /// Expected regular expression pattern.
  final String matches;

  /// Expected schema for structured output.
  final Map<String, dynamic> schema;

  /// Human-facing failure message.
  final String message;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses validation assertion metadata from decoded YAML.
  factory ToolValidationAssertionConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('type')
      ..remove('path')
      ..remove('equals')
      ..remove('contains')
      ..remove('matches')
      ..remove('schema')
      ..remove('message');
    return ToolValidationAssertionConfig(
      type: stringValue(map['type'], trim: true),
      path: stringValue(map['path'], trim: true),
      equals: map['equals'],
      contains: stringValue(map['contains'], trim: true),
      matches: stringValue(map['matches'], trim: true),
      schema: jsonObject(map['schema']),
      message: stringValue(map['message'], trim: true),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  ToolValidationAssertionConfig copyWith({
    String? type,
    String? path,
    dynamic equals = _unchangedToolAssertionValue,
    String? contains,
    String? matches,
    Map<String, dynamic>? schema,
    String? message,
    Map<String, dynamic>? extra,
  }) {
    return ToolValidationAssertionConfig(
      type: type ?? this.type,
      path: path ?? this.path,
      equals: identical(equals, _unchangedToolAssertionValue)
          ? this.equals
          : equals,
      contains: contains ?? this.contains,
      matches: matches ?? this.matches,
      schema: schema ?? this.schema,
      message: message ?? this.message,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes this assertion as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'type': type,
      if (path.isNotEmpty) 'path': path,
      if (equals != null) 'equals': equals,
      if (contains.isNotEmpty) 'contains': contains,
      if (matches.isNotEmpty) 'matches': matches,
      if (schema.isNotEmpty) 'schema': schema,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

const Object _unchangedToolAssertionValue = Object();

/// Returns an empty tool config document.
ToolConfigDocument emptyToolConfigDocument() {
  return const ToolConfigDocument(
    localExec: LocalExecToolConfig(
      enabled: false,
      defaultTimeout: '',
      defaultMaxOutputBytes: 0,
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
    installation: LocalExecInstallationConfig.fromMap(
      const <String, dynamic>{},
    ),
    surface: const LocalExecCommandSurfaceConfig(
      globalFlags: <LocalExecCommandFlagConfig>[],
      subcommands: <LocalExecSubcommandConfig>[],
    ),
    operations: const <LocalExecOperationConfig>[],
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
  List<McpServerRuntime> mcpServers = const <McpServerRuntime>[],
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
        for (final server in mcpServers)
          if (server.enabled)
            newHttpMcpServerToolConfig(
              name: _serviceMcpToolServerName(server),
              endpoint: server.endpoint,
            ).copyWith(
              tools: McpToolFilterConfig(
                allow: _serviceMcpToolAllowlist(server),
              ),
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

/// Returns an allowlist for profile-owned generic MCP service kinds.
List<String> _serviceMcpToolAllowlist(McpServerRuntime server) {
  return switch (server.kind) {
    'sourcecontrol' => sourceControlMcpToolNames,
    _ => const <String>[],
  };
}

/// Returns a stable harness MCP server name for a profile-owned service.
String _serviceMcpToolServerName(McpServerRuntime server) {
  final source = server.kind.trim().isEmpty ? server.id : server.kind;
  return source.replaceAll('-', '_');
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
  final mcpError = _mcpValidationError(document.mcp);
  if (mcpError.isNotEmpty) {
    return mcpError;
  }
  return _toolMetadataValidationError(document);
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
  for (final flag in command.surface.globalFlags) {
    if (flag.name.trim().isEmpty) {
      return 'local-exec command "$name" global flag name must not be empty';
    }
  }
  final subcommands = <String>{};
  for (final subcommand in command.surface.subcommands) {
    final subcommandName = subcommand.name.trim();
    if (subcommandName.isEmpty) {
      return 'local-exec command "$name" subcommand name must not be empty';
    }
    if (!subcommands.add(subcommandName)) {
      return 'local-exec command "$name" duplicate subcommand "$subcommandName"';
    }
    for (final flag in subcommand.flags) {
      if (flag.name.trim().isEmpty) {
        return 'local-exec command "$name" subcommand "$subcommandName" flag name must not be empty';
      }
    }
  }
  final operations = <String>{};
  for (final operation in command.operations) {
    final operationName = operation.name.trim();
    if (operationName.isEmpty) {
      return 'local-exec command "$name" operation name must not be empty';
    }
    if (!_toolNamePattern.hasMatch(operationName)) {
      return 'local-exec command "$name" operation "$operationName" uses an invalid name';
    }
    if (!operations.add(operationName)) {
      return 'local-exec command "$name" duplicate operation "$operationName"';
    }
    if (operation.description.trim().isEmpty) {
      return 'local-exec command "$name" operation "$operationName" description must not be empty';
    }
    if (operation.timeout.trim().isNotEmpty &&
        !_isGoDuration(operation.timeout)) {
      return 'local-exec command "$name" operation "$operationName" timeout must be a Go duration';
    }
    if (operation.maxOutputBytes < 0) {
      return 'local-exec command "$name" operation "$operationName" max-output-bytes must not be negative';
    }
    final format = operation.output.format.trim().toLowerCase();
    if (format.isNotEmpty &&
        !const <String>{'json', 'text', 'plain'}.contains(format)) {
      return 'local-exec command "$name" operation "$operationName" output format must be json, text, or plain';
    }
    final source = operation.output.source.trim().toLowerCase();
    if (source.isNotEmpty &&
        !const <String>{'stdout', 'stderr', 'combined'}.contains(source)) {
      return 'local-exec command "$name" operation "$operationName" output source must be stdout, stderr, or combined';
    }
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

/// Returns a validation error for node preset and portable validation metadata.
String _toolMetadataValidationError(ToolConfigDocument document) {
  final operations = <String, Set<String>>{};
  final commandTemplateIds = <String>{};
  for (final command in document.localExec.commands) {
    final commandName = command.name.trim();
    operations[commandName] = command.operations
        .map((operation) => operation.name.trim())
        .where((operation) => operation.isNotEmpty)
        .toSet();
    if (commandName.isEmpty) {
      continue;
    }
    if (command.operations.isEmpty) {
      commandTemplateIds.add(commandName);
    } else {
      for (final operation in command.operations) {
        final operationName = operation.name.trim();
        if (operationName.isNotEmpty) {
          commandTemplateIds.add('$commandName.$operationName');
        }
      }
    }
  }
  final mcpTools = <String, Set<String>>{};
  for (final server in document.mcp.servers) {
    mcpTools[server.name.trim()] = server.tools.allow
        .map((tool) => tool.trim())
        .where((tool) => tool.isNotEmpty)
        .toSet();
  }
  final presetIds = <String>{};
  for (final preset in document.nodePresets) {
    final id = preset.id.trim();
    if (id.isEmpty) {
      return 'node preset id must not be empty';
    }
    if (!_toolNamePattern.hasMatch(id)) {
      return 'node preset "$id" uses an invalid id';
    }
    if (!presetIds.add(id)) {
      return 'node preset duplicate "$id"';
    }
    if (preset.action != 'command.execute' && preset.action != 'mcp.call') {
      return 'node preset "$id" action must be command.execute or mcp.call';
    }
    final presetError = _nodePresetArgumentsValidationError(
      id,
      preset,
      commandTemplateIds,
      mcpTools,
    );
    if (presetError.isNotEmpty) {
      return presetError;
    }
  }
  final validationIds = <String>{};
  for (final validation in document.validations) {
    final id = validation.id.trim();
    if (id.isEmpty) {
      return 'validation id must not be empty';
    }
    if (!_toolNamePattern.hasMatch(id)) {
      return 'validation "$id" uses an invalid id';
    }
    if (!validationIds.add(id)) {
      return 'validation duplicate "$id"';
    }
    final mode = validation.mode.trim();
    if (mode.isNotEmpty && mode != 'mocked' && mode != 'live') {
      return 'validation "$id" mode must be mocked or live';
    }
    final targetError = _toolValidationTargetError(
      id,
      validation,
      presetIds,
      operations,
      mcpTools,
    );
    if (targetError.isNotEmpty) {
      return targetError;
    }
    for (var index = 0; index < validation.assertions.length; index++) {
      final assertion = validation.assertions[index];
      if (!const <String>{
        'status',
        'exit-code',
        'json-path',
        'stdout-contains',
        'stderr-contains',
        'schema',
      }.contains(assertion.type.trim())) {
        return 'validation "$id" assertion ${index + 1} uses an unsupported type';
      }
    }
  }
  return '';
}

/// Returns a validation error for one reusable workflow node preset.
String _nodePresetArgumentsValidationError(
  String id,
  NodePresetConfig preset,
  Set<String> commandTemplateIds,
  Map<String, Set<String>> mcpTools,
) {
  switch (preset.action.trim()) {
    case 'command.execute':
      final templateId = stringValue(
        preset.arguments['template_id'],
        trim: true,
      );
      if (templateId.isEmpty) {
        return 'node preset "$id" command.execute needs template_id';
      }
      if (!commandTemplateIds.contains(templateId)) {
        return 'node preset "$id" references unknown command template "$templateId"';
      }
    case 'mcp.call':
      final serverId = stringValue(preset.arguments['server_id'], trim: true);
      final tool = stringValue(preset.arguments['tool'], trim: true);
      if (serverId.isEmpty || tool.isEmpty) {
        return 'node preset "$id" mcp.call needs server_id and tool';
      }
      final serverTools = mcpTools[serverId];
      if (serverTools == null) {
        return 'node preset "$id" references unknown MCP server "$serverId"';
      }
      if (!serverTools.contains(tool)) {
        return 'node preset "$id" references unknown MCP tool "$tool" on server "$serverId"';
      }
  }
  return '';
}

/// Returns a validation error for one portable validation target.
String _toolValidationTargetError(
  String id,
  ToolValidationConfig validation,
  Set<String> presetIds,
  Map<String, Set<String>> operations,
  Map<String, Set<String>> mcpTools,
) {
  final target = validation.target;
  switch (target.type.trim()) {
    case 'workflow-node':
      final preset = target.presetId.trim();
      final command = target.command.trim();
      final operation = target.operation.trim();
      final server = target.mcpServer.trim();
      final tool = target.mcpTool.trim();
      final hasPreset = preset.isNotEmpty;
      final hasCommand = command.isNotEmpty || operation.isNotEmpty;
      final hasMcp = server.isNotEmpty || tool.isNotEmpty;
      final selected = <bool>[
        hasPreset,
        hasCommand,
        hasMcp,
      ].where((value) => value).length;
      if (selected > 1) {
        return 'validation "$id" workflow-node target must choose preset-id, command-operation, or mcp-tool';
      }
      if (hasCommand) {
        return _commandOperationTargetError(
          id,
          target,
          operations,
          'workflow-node',
        );
      }
      if (hasMcp) {
        return _mcpToolTargetError(id, target, mcpTools, 'workflow-node');
      }
      if (!presetIds.contains(preset)) {
        return 'validation "$id" references unknown preset "$preset"';
      }
    case 'command-operation':
      return _commandOperationTargetError(
        id,
        target,
        operations,
        'command-operation',
      );
    case 'mcp-tool':
      return _mcpToolTargetError(id, target, mcpTools, 'mcp-tool');
    case 'agent-tool-call':
      if (validation.prompt.trim().isEmpty) {
        return 'validation "$id" agent-tool-call target needs a prompt';
      }
      return _agentToolCallTargetError(id, target, operations, mcpTools);
    case '':
      return 'validation "$id" target type must not be empty';
    default:
      return 'validation "$id" target type must be workflow-node, command-operation, mcp-tool, or agent-tool-call';
  }
  return '';
}

/// Returns a validation error for an MCP tool target.
String _mcpToolTargetError(
  String id,
  ToolValidationTargetConfig target,
  Map<String, Set<String>> mcpTools,
  String targetType,
) {
  final server = target.mcpServer.trim();
  final tool = target.mcpTool.trim();
  if (server.isEmpty || tool.isEmpty) {
    return 'validation "$id" $targetType target needs mcp-server and mcp-tool';
  }
  if (!mcpTools.containsKey(server)) {
    return 'validation "$id" references unknown MCP server "$server"';
  }
  if (!mcpTools[server]!.contains(tool)) {
    return 'validation "$id" references unknown MCP tool "$tool" on server "$server"';
  }
  return '';
}

/// Returns a validation error for a command operation target.
String _commandOperationTargetError(
  String id,
  ToolValidationTargetConfig target,
  Map<String, Set<String>> operations,
  String targetType,
) {
  final command = target.command.trim();
  final operation = target.operation.trim();
  if (command.isEmpty || operation.isEmpty) {
    return 'validation "$id" $targetType target needs command and operation';
  }
  if (!operations.containsKey(command)) {
    return 'validation "$id" references unknown command "$command"';
  }
  if (!operations[command]!.contains(operation)) {
    return 'validation "$id" references unknown operation "$operation" on command "$command"';
  }
  return '';
}

/// Returns a validation error for an agent-selected tool target.
String _agentToolCallTargetError(
  String id,
  ToolValidationTargetConfig target,
  Map<String, Set<String>> operations,
  Map<String, Set<String>> mcpTools,
) {
  final command = target.command.trim();
  final operation = target.operation.trim();
  final server = target.mcpServer.trim();
  final tool = target.mcpTool.trim();
  final hasCommand = command.isNotEmpty || operation.isNotEmpty;
  final hasMcp = server.isNotEmpty || tool.isNotEmpty;
  if (hasCommand && hasMcp) {
    return 'validation "$id" agent-tool-call target must choose command-operation or mcp-tool, not both';
  }
  if (hasCommand) {
    if (command.isEmpty || operation.isEmpty) {
      return 'validation "$id" agent-tool-call command target needs command and operation';
    }
    if (!operations.containsKey(command)) {
      return 'validation "$id" references unknown command "$command"';
    }
    if (!operations[command]!.contains(operation)) {
      return 'validation "$id" references unknown operation "$operation" on command "$command"';
    }
    return '';
  }
  if (hasMcp) {
    return _mcpToolTargetError(id, target, mcpTools, 'agent-tool-call MCP');
  }
  return 'validation "$id" agent-tool-call target needs command-operation or mcp-tool';
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
