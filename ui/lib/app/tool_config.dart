/// Parses and writes harness tool configuration files.
library;

import 'dart:convert';

import 'package:yaml/yaml.dart';

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
    final decoded = _plainYaml(loadYaml(content));
    if (decoded is! Map<String, dynamic>) {
      return emptyToolConfigDocument();
    }
    final extra = Map<String, dynamic>.from(decoded)
      ..remove('local-exec')
      ..remove('local_exec')
      ..remove('mcp');
    return ToolConfigDocument(
      localExec: LocalExecToolConfig.fromMap(
        _mapValue(decoded['local-exec'] ?? decoded['local_exec']),
      ),
      mcp: McpToolConfig.fromMap(_mapValue(decoded['mcp'])),
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
    return _yamlMap(toJson());
  }
}

/// LocalExecToolConfig describes configured local command execution tools.
class LocalExecToolConfig {
  /// Creates local execution tool settings.
  const LocalExecToolConfig({
    required this.enabled,
    required this.requireConfirmation,
    required this.defaultTimeout,
    required this.defaultMaxOutputBytes,
    required this.allowedWorkdirs,
    required this.commands,
    this.extra = const <String, dynamic>{},
  });

  /// Whether local command tools are installed on the agent.
  final bool enabled;

  /// Optional schema value; when present the harness only accepts true.
  final bool? requireConfirmation;

  /// Default Go-style duration for command execution.
  final String defaultTimeout;

  /// Default captured output limit in bytes.
  final int defaultMaxOutputBytes;

  /// Workspace roots where commands may run.
  final List<String> allowedWorkdirs;

  /// Allowlisted command aliases exposed through local_exec.
  final List<LocalExecCommandConfig> commands;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses local-exec settings from decoded YAML.
  factory LocalExecToolConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('enabled')
      ..remove('require-confirmation')
      ..remove('require_confirmation')
      ..remove('default-timeout')
      ..remove('default_timeout')
      ..remove('default-max-output-bytes')
      ..remove('default_max_output_bytes')
      ..remove('allowed-workdirs')
      ..remove('allowed_workdirs')
      ..remove('commands');
    return LocalExecToolConfig(
      enabled: _configBool(map['enabled']),
      requireConfirmation: _nullableBool(
        map['require-confirmation'] ?? map['require_confirmation'],
      ),
      defaultTimeout: _configString(
        map['default-timeout'] ?? map['default_timeout'],
      ),
      defaultMaxOutputBytes: _configInt(
        map['default-max-output-bytes'] ?? map['default_max_output_bytes'],
      ),
      allowedWorkdirs: _stringList(
        map['allowed-workdirs'] ?? map['allowed_workdirs'],
      ),
      commands: _mapList(
        map['commands'],
      ).map(LocalExecCommandConfig.fromMap).toList(),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecToolConfig copyWith({
    bool? enabled,
    Object? requireConfirmation = _unset,
    String? defaultTimeout,
    int? defaultMaxOutputBytes,
    List<String>? allowedWorkdirs,
    List<LocalExecCommandConfig>? commands,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecToolConfig(
      enabled: enabled ?? this.enabled,
      requireConfirmation: identical(requireConfirmation, _unset)
          ? this.requireConfirmation
          : requireConfirmation as bool?,
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
      if (requireConfirmation != null)
        'require-confirmation': requireConfirmation,
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
    required this.approval,
    this.extra = const <String, dynamic>{},
  });

  /// Alias the model uses when calling local_exec.
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

  /// Approval shortcuts for this command.
  final LocalExecApprovalConfig approval;

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
      ..remove('approval');
    return LocalExecCommandConfig(
      name: _configString(map['name']),
      executable: _configString(map['executable']),
      description: _configString(map['description']),
      args: _stringList(map['args']),
      timeout: _configString(map['timeout']),
      maxOutputBytes: _configInt(
        map['max-output-bytes'] ?? map['max_output_bytes'],
      ),
      approval: LocalExecApprovalConfig.fromMap(_mapValue(map['approval'])),
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
    LocalExecApprovalConfig? approval,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecCommandConfig(
      name: name ?? this.name,
      executable: executable ?? this.executable,
      description: description ?? this.description,
      args: args ?? this.args,
      timeout: timeout ?? this.timeout,
      maxOutputBytes: maxOutputBytes ?? this.maxOutputBytes,
      approval: approval ?? this.approval,
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
      'approval': approval.toJson(),
    };
  }
}

/// LocalExecApprovalConfig describes command approval shortcuts.
class LocalExecApprovalConfig {
  /// Creates approval shortcut settings.
  const LocalExecApprovalConfig({
    required this.alwaysAllowWithinWorkspace,
    required this.alwaysAllowCommandPrefixes,
    required this.alwaysAllow,
    this.extra = const <String, dynamic>{},
  });

  /// Whether the command can run automatically inside the current workspace.
  final bool alwaysAllowWithinWorkspace;

  /// Command-line prefixes that bypass one-off confirmation.
  final List<String> alwaysAllowCommandPrefixes;

  /// Whether every invocation of this alias is approved automatically.
  final bool alwaysAllow;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses approval settings from decoded YAML.
  factory LocalExecApprovalConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('always-allow-within-workspace')
      ..remove('always_allow_within_workspace')
      ..remove('always-allow-command-starts-with')
      ..remove('always_allow_command_starts_with')
      ..remove('always-allow')
      ..remove('always_allow');
    return LocalExecApprovalConfig(
      alwaysAllowWithinWorkspace: _configBool(
        map['always-allow-within-workspace'] ??
            map['always_allow_within_workspace'],
      ),
      alwaysAllowCommandPrefixes: _stringList(
        map['always-allow-command-starts-with'] ??
            map['always_allow_command_starts_with'],
      ),
      alwaysAllow: _configBool(map['always-allow'] ?? map['always_allow']),
      extra: extra,
    );
  }

  /// Returns a copy with selected values changed.
  LocalExecApprovalConfig copyWith({
    bool? alwaysAllowWithinWorkspace,
    List<String>? alwaysAllowCommandPrefixes,
    bool? alwaysAllow,
    Map<String, dynamic>? extra,
  }) {
    return LocalExecApprovalConfig(
      alwaysAllowWithinWorkspace:
          alwaysAllowWithinWorkspace ?? this.alwaysAllowWithinWorkspace,
      alwaysAllowCommandPrefixes:
          alwaysAllowCommandPrefixes ?? this.alwaysAllowCommandPrefixes,
      alwaysAllow: alwaysAllow ?? this.alwaysAllow,
      extra: extra ?? this.extra,
    );
  }

  /// Encodes approval settings as JSON-compatible data.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      ...extra,
      'always-allow-within-workspace': alwaysAllowWithinWorkspace,
      if (alwaysAllowCommandPrefixes.isNotEmpty)
        'always-allow-command-starts-with': alwaysAllowCommandPrefixes,
      'always-allow': alwaysAllow,
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

  /// MCP servers exposed as ADK toolsets.
  final List<McpServerToolConfig> servers;

  /// Fields preserved outside the known schema.
  final Map<String, dynamic> extra;

  /// Parses MCP settings from decoded YAML.
  factory McpToolConfig.fromMap(Map<String, dynamic> map) {
    final extra = Map<String, dynamic>.from(map)
      ..remove('enabled')
      ..remove('servers');
    return McpToolConfig(
      enabled: _configBool(map['enabled']),
      servers: _mapList(
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
      ..remove('endpoint')
      ..remove('url')
      ..remove('require-confirmation')
      ..remove('require_confirmation')
      ..remove('require-confirmation-tools')
      ..remove('require_confirmation_tools')
      ..remove('tools');
    return McpServerToolConfig(
      name: _configString(map['name']),
      transport: _configString(map['transport'], fallback: 'streamable-http'),
      command: _configString(map['command']),
      args: _stringList(map['args']),
      env: _stringMap(map['env']),
      endpoint: _configString(map['endpoint']),
      url: _configString(map['url']),
      requireConfirmation: _configBool(
        map['require-confirmation'] ?? map['require_confirmation'],
      ),
      requireConfirmationTools: _stringList(
        map['require-confirmation-tools'] ?? map['require_confirmation_tools'],
      ),
      tools: McpToolFilterConfig.fromMap(_mapValue(map['tools'])),
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
    return McpToolFilterConfig(allow: _stringList(map['allow']), extra: extra);
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
      requireConfirmation: null,
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
    approval: const LocalExecApprovalConfig(
      alwaysAllowWithinWorkspace: false,
      alwaysAllowCommandPrefixes: <String>[],
      alwaysAllow: false,
    ),
  );
}

/// Creates a streamable HTTP MCP server entry.
McpServerToolConfig newHttpMcpServerToolConfig({
  required String name,
  required String endpoint,
}) {
  return McpServerToolConfig(
    name: name,
    transport: 'streamable-http',
    command: '',
    args: const <String>[],
    env: const <String, String>{},
    endpoint: endpoint,
    url: '',
    requireConfirmation: false,
    requireConfirmationTools: const <String>[],
    tools: const McpToolFilterConfig(allow: <String>[]),
  );
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
  if (config.requireConfirmation == false) {
    return 'local-exec require-confirmation must be true';
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
  if (command.approval.alwaysAllowCommandPrefixes.any(
    (value) => value.trim().isEmpty,
  )) {
    return 'local-exec command "$name" approval prefixes must not be empty';
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

/// Converts YAML package collection values to plain Dart values.
dynamic _plainYaml(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _plainYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return value.map(_plainYaml).toList();
  }
  return value;
}

/// Converts a decoded value to a map.
Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  return const <String, dynamic>{};
}

/// Converts a decoded value to a list of maps.
List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is List) {
    return value.whereType<Map<String, dynamic>>().toList();
  }
  return const <Map<String, dynamic>>[];
}

/// Converts a decoded scalar to a config string.
String _configString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Converts a decoded scalar to a bool.
bool _configBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  return value.toString().trim().toLowerCase() == 'true';
}

/// Converts a decoded scalar to a nullable bool.
bool? _nullableBool(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  return null;
}

/// Converts a decoded scalar to an integer.
int _configInt(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString().trim() ?? '') ?? 0;
}

/// Converts a decoded value to a trimmed string list.
List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
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

/// Encodes a map as readable YAML.
String _yamlMap(Map<String, dynamic> map) {
  final buffer = StringBuffer();
  _writeYamlMap(buffer, map, 0);
  return buffer.toString();
}

/// Writes a YAML map with stable indentation.
void _writeYamlMap(StringBuffer buffer, Map<String, dynamic> map, int indent) {
  for (final entry in map.entries) {
    _writeYamlMapEntry(buffer, entry.key, entry.value, indent);
  }
}

/// Writes one YAML map entry, optionally prefixed by a list marker.
void _writeYamlMapEntry(
  StringBuffer buffer,
  String key,
  dynamic value,
  int indent, {
  String prefix = '',
}) {
  final padding = ' ' * indent;
  final entryPrefix = '$padding$prefix$key:';
  final childIndent = indent + prefix.length + 2;
  if (value is Map<String, dynamic>) {
    if (value.isEmpty) {
      buffer.writeln('$entryPrefix {}');
      return;
    }
    buffer.writeln(entryPrefix);
    _writeYamlMap(buffer, value, childIndent);
  } else if (value is List) {
    if (value.isEmpty) {
      buffer.writeln('$entryPrefix []');
      return;
    }
    buffer.writeln(entryPrefix);
    _writeYamlList(buffer, value, childIndent);
  } else {
    buffer.writeln('$entryPrefix ${_yamlScalar(value)}');
  }
}

/// Writes a YAML list with stable indentation.
void _writeYamlList(StringBuffer buffer, List<dynamic> list, int indent) {
  for (final value in list) {
    final prefix = ' ' * indent;
    if (value is Map<String, dynamic>) {
      if (value.isEmpty) {
        buffer.writeln('$prefix- {}');
        continue;
      }
      final entries = value.entries.toList(growable: false);
      final first = entries.first;
      _writeYamlMapEntry(buffer, first.key, first.value, indent, prefix: '- ');
      for (final entry in entries.skip(1)) {
        _writeYamlMapEntry(buffer, entry.key, entry.value, indent + 2);
      }
    } else {
      buffer.writeln('$prefix- ${_yamlScalar(value)}');
    }
  }
}

/// Encodes one YAML scalar conservatively.
String _yamlScalar(dynamic value) {
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value == null) {
    return 'null';
  }
  final text = value.toString();
  if (text.isEmpty ||
      text.contains(': ') ||
      text.startsWith('{') ||
      text.startsWith('[') ||
      text.contains('\n')) {
    return jsonEncode(text);
  }
  return text;
}

const Object _unset = Object();
final RegExp _toolNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');
final RegExp _goDurationPattern = RegExp(
  r'^(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+$',
);
