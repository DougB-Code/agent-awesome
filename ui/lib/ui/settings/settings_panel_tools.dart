/// Tool configuration, local-exec, and MCP settings widgets.
part of 'settings_panel.dart';

class _SettingsToolConfigCollection extends StatefulWidget {
  const _SettingsToolConfigCollection({
    required this.controller,
    required this.emptyLabel,
    required this.entries,
    required this.assignedPath,
  });

  final AgentAwesomeAppController controller;
  final String emptyLabel;
  final List<ConfigFileEntry> entries;
  final String assignedPath;

  /// Creates state for structured harness tool config editing.
  @override
  State<_SettingsToolConfigCollection> createState() =>
      _SettingsToolConfigCollectionState();
}

class _SettingsToolConfigCollectionState
    extends State<_SettingsToolConfigCollection> {
  String? _selectedPath;
  _ToolSettingsSurface _selectedSurface = _ToolSettingsSurface.osTools;

  /// Initializes selected tool config state.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
  }

  /// Keeps selected tool config state valid after collection updates.
  @override
  void didUpdateWidget(covariant _SettingsToolConfigCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPath == null ||
        !widget.entries.any((entry) => entry.path == _selectedPath)) {
      _selectedPath = _initialSelectedPath();
    }
  }

  /// Builds the tool-family switcher for the selected harness tool config.
  @override
  Widget build(BuildContext context) {
    final selectedEntry = _selectedEntry();
    return CollectionSwitcherPanel<_ToolSettingsSurface>(
      title: 'Tools',
      selectedId: _selectedSurface.id,
      emptyLabel: widget.emptyLabel,
      items: <CollectionPanelItem<_ToolSettingsSurface>>[
        CollectionPanelItem<_ToolSettingsSurface>(
          id: _ToolSettingsSurface.osTools.id,
          label: 'OS Tools',
          detail: 'Local command aliases and approval rules.',
          icon: Icons.terminal,
          value: _ToolSettingsSurface.osTools,
        ),
        CollectionPanelItem<_ToolSettingsSurface>(
          id: _ToolSettingsSurface.mcpServer.id,
          label: 'MCP Server',
          detail: 'MCP server toolsets and tool policy.',
          icon: Icons.hub_outlined,
          value: _ToolSettingsSurface.mcpServer,
        ),
      ],
      onSelect: (id) => setState(() {
        _selectedSurface = _ToolSettingsSurface.fromId(id);
      }),
      builder: (surface, query) {
        final entry = selectedEntry;
        if (entry == null) {
          return _SettingsMissingToolConfig(
            label: widget.emptyLabel,
            onCreate: () => unawaited(_create()),
          );
        }
        return _SettingsToolConfigEditor(
          controller: widget.controller,
          entry: entry,
          entries: widget.entries,
          surface: surface,
          query: query,
          onConfigSelected: (entry) {
            setState(() => _selectedPath = entry.path);
          },
          onCreateConfig: () => unawaited(_create()),
          onDuplicateConfig: () => unawaited(_duplicate(entry)),
          onDeleteConfig: () => unawaited(_delete(entry)),
        );
      },
    );
  }

  /// Returns the selected tool config entry.
  ConfigFileEntry? _selectedEntry() {
    final selectedPath = _selectedPath;
    if (selectedPath != null) {
      for (final entry in widget.entries) {
        if (entry.path == selectedPath) {
          return entry;
        }
      }
    }
    if (widget.entries.isEmpty) {
      return null;
    }
    return widget.entries.first;
  }

  /// Returns the initially selected config path.
  String? _initialSelectedPath() {
    if (widget.assignedPath.isNotEmpty &&
        widget.entries.any((entry) => entry.path == widget.assignedPath)) {
      return widget.assignedPath;
    }
    if (widget.entries.isEmpty) {
      return null;
    }
    return widget.entries.first.path;
  }

  /// Creates a new tool config file.
  Future<void> _create() async {
    try {
      final path = await widget.controller.createConfigFile(
        ConfigFileKind.tool,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPath = path;
      });
    } catch (_) {}
  }

  /// Duplicates an existing tool config file.
  Future<void> _duplicate(ConfigFileEntry entry) async {
    try {
      final path = await widget.controller.duplicateConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPath = path;
      });
    } catch (_) {}
  }

  /// Deletes an unassigned tool config file.
  Future<void> _delete(ConfigFileEntry entry) async {
    final confirmed = await _confirmSettingsDelete(context, label: entry.label);
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPath = _initialSelectedPath();
      });
    } catch (_) {}
  }
}

enum _ToolSettingsSurface {
  osTools,
  mcpServer;

  /// Stable id used by the tools settings switcher.
  String get id {
    return switch (this) {
      _ToolSettingsSurface.osTools => 'os-tools',
      _ToolSettingsSurface.mcpServer => 'mcp-server',
    };
  }

  /// Returns a surface from a stable switcher id.
  static _ToolSettingsSurface fromId(String id) {
    return switch (id) {
      'mcp-server' => _ToolSettingsSurface.mcpServer,
      _ => _ToolSettingsSurface.osTools,
    };
  }
}

class _SettingsMissingToolConfig extends StatelessWidget {
  const _SettingsMissingToolConfig({
    required this.label,
    required this.onCreate,
  });

  final String label;
  final VoidCallback onCreate;

  /// Builds the empty state shown before a tool config file exists.
  @override
  Widget build(BuildContext context) {
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          title: 'Tool config',
          children: <Widget>[
            PanelEmptyBlock(label: label),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Add tool config'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsToolConfigEditor extends StatefulWidget {
  const _SettingsToolConfigEditor({
    required this.controller,
    required this.entry,
    required this.entries,
    required this.surface,
    required this.query,
    required this.onConfigSelected,
    required this.onCreateConfig,
    required this.onDuplicateConfig,
    required this.onDeleteConfig,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final List<ConfigFileEntry> entries;
  final _ToolSettingsSurface surface;
  final String query;
  final ValueChanged<ConfigFileEntry> onConfigSelected;
  final VoidCallback onCreateConfig;
  final VoidCallback onDuplicateConfig;
  final VoidCallback onDeleteConfig;

  /// Creates state for editing structured tool config content.
  @override
  State<_SettingsToolConfigEditor> createState() =>
      _SettingsToolConfigEditorState();
}

class _SettingsToolConfigEditorState extends State<_SettingsToolConfigEditor> {
  ToolConfigDocument? _document;
  bool _loading = true;

  /// Loads the selected tool config file.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reloads structured state when the selected file changes.
  @override
  void didUpdateWidget(covariant _SettingsToolConfigEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _document = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds the selected tool config editor.
  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document != null &&
        !SettingsQuery.matches(
          widget.query,
          _searchValues(document, widget.surface),
        )) {
      return PanelEmptyState(query: widget.query);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (document == null) {
      return FormPanel(
        children: <Widget>[
          FormSectionCard(
            title: 'Tool config',
            children: <Widget>[
              _SettingsReadOnlyField(label: 'Path', value: widget.entry.path),
            ],
          ),
        ],
      );
    }
    return FormPanel(
      children: <Widget>[
        _SettingsToolFileCard(
          entry: widget.entry,
          entries: widget.entries,
          onSelected: widget.onConfigSelected,
          onAssign: widget.entry.assigned ? null : _assign,
          onCreate: widget.onCreateConfig,
          onDuplicate: widget.onDuplicateConfig,
          onDelete: widget.onDeleteConfig,
        ),
        if (widget.surface == _ToolSettingsSurface.osTools)
          _SettingsLocalExecCard(
            config: document.localExec,
            onChanged: (localExec) {
              unawaited(_save(document.copyWith(localExec: localExec)));
            },
            onAddCommand: () => unawaited(_addCommand(document)),
            onDeleteCommand: (index) =>
                unawaited(_deleteCommand(document, index)),
            onCommandChanged: (index, command) {
              final commands = <LocalExecCommandConfig>[
                for (var i = 0; i < document.localExec.commands.length; i++)
                  i == index ? command : document.localExec.commands[i],
              ];
              unawaited(
                _save(
                  document.copyWith(
                    localExec: document.localExec.copyWith(commands: commands),
                  ),
                ),
              );
            },
          )
        else
          _SettingsMcpToolsetsCard(
            config: document.mcp,
            profileServers:
                widget.controller.runtimeProfile?.mcpServers ??
                const <McpServerRuntime>[],
            onChanged: (mcp) {
              unawaited(_save(document.copyWith(mcp: mcp)));
            },
            onAddServer: () => unawaited(_addMcpServer(document)),
            onDeleteServer: (index) =>
                unawaited(_deleteMcpServer(document, index)),
            onServerChanged: (index, server) {
              final servers = <McpServerToolConfig>[
                for (var i = 0; i < document.mcp.servers.length; i++)
                  i == index ? server : document.mcp.servers[i],
              ];
              unawaited(
                _save(
                  document.copyWith(
                    mcp: document.mcp.copyWith(servers: servers),
                  ),
                ),
              );
            },
          ),
        _SettingsToolYamlPreview(document: document),
      ],
    );
  }

  /// Returns values used by the selected-surface search filter.
  List<String> _searchValues(
    ToolConfigDocument document,
    _ToolSettingsSurface surface,
  ) {
    final base = <String>[widget.entry.label, widget.entry.path];
    return switch (surface) {
      _ToolSettingsSurface.osTools => <String>[
        ...base,
        'OS Tools',
        'local_exec',
        'request_command',
        for (final command in document.localExec.commands) ...<String>[
          command.name,
          command.executable,
          command.description,
          command.args.join(' '),
        ],
      ],
      _ToolSettingsSurface.mcpServer => <String>[
        ...base,
        'MCP Server',
        for (final server in document.mcp.servers) ...<String>[
          server.name,
          server.transport,
          server.command,
          mcpServerEndpoint(server),
          server.tools.allow.join(' '),
        ],
      ],
    };
  }

  /// Loads and parses the selected tool config.
  Future<void> _load() async {
    try {
      final content = await widget.controller.readConfigurationFile(
        widget.entry.path,
      );
      final document = ToolConfigDocument.parse(content);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _document = null;
        _loading = false;
      });
    }
  }

  /// Assigns the selected tool config file to the active profile.
  Future<void> _assign() async {
    try {
      await widget.controller.assignConfigFile(widget.entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Saves a typed tool config document after local validation.
  Future<void> _save(ToolConfigDocument document) async {
    final validationError = toolConfigValidationError(document);
    if (validationError.isNotEmpty) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(
        widget.entry.path,
        document.toYaml(),
      );
      await widget.controller.refreshConfigurationCollections();
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
      });
    } catch (_) {}
  }

  /// Adds a configured local command through a required-field dialog.
  Future<void> _addCommand(ToolConfigDocument document) async {
    final command = await showDialog<LocalExecCommandConfig>(
      context: context,
      builder: (context) {
        return const _LocalExecCommandDialog();
      },
    );
    if (command == null) {
      return;
    }
    final localExec = document.localExec.copyWith(
      enabled: true,
      commands: <LocalExecCommandConfig>[
        ...document.localExec.commands,
        command,
      ],
    );
    await _save(document.copyWith(localExec: localExec));
  }

  /// Deletes a configured local command and disables local-exec if empty.
  Future<void> _deleteCommand(ToolConfigDocument document, int index) async {
    final command = document.localExec.commands[index];
    final confirmed = await _confirmSettingsDelete(
      context,
      label: command.name,
    );
    if (!confirmed) {
      return;
    }
    final commands = <LocalExecCommandConfig>[
      for (var i = 0; i < document.localExec.commands.length; i++)
        if (i != index) document.localExec.commands[i],
    ];
    await _save(
      document.copyWith(
        localExec: document.localExec.copyWith(
          enabled: commands.isNotEmpty && document.localExec.enabled,
          commands: commands,
        ),
      ),
    );
  }

  /// Adds an MCP server through a required-field dialog.
  Future<void> _addMcpServer(ToolConfigDocument document) async {
    final server = await showDialog<McpServerToolConfig>(
      context: context,
      builder: (context) {
        return _McpServerDialog(seed: _suggestedProfileServer(document));
      },
    );
    if (server == null) {
      return;
    }
    await _save(
      document.copyWith(
        mcp: document.mcp.copyWith(
          enabled: true,
          servers: <McpServerToolConfig>[...document.mcp.servers, server],
        ),
      ),
    );
  }

  /// Deletes an MCP server and disables MCP if no servers remain.
  Future<void> _deleteMcpServer(ToolConfigDocument document, int index) async {
    final server = document.mcp.servers[index];
    final confirmed = await _confirmSettingsDelete(context, label: server.name);
    if (!confirmed) {
      return;
    }
    final servers = <McpServerToolConfig>[
      for (var i = 0; i < document.mcp.servers.length; i++)
        if (i != index) document.mcp.servers[i],
    ];
    await _save(
      document.copyWith(
        mcp: document.mcp.copyWith(
          enabled: servers.isNotEmpty && document.mcp.enabled,
          servers: servers,
        ),
      ),
    );
  }

  /// Returns a profile MCP server not already present in the tool config.
  McpServerRuntime? _suggestedProfileServer(ToolConfigDocument document) {
    final existingNames = document.mcp.servers.map((server) => server.name);
    for (final server
        in widget.controller.runtimeProfile?.mcpServers ??
            const <McpServerRuntime>[]) {
      final name = SettingsNameFactory.toolNameFromLabel(
        server.kind.isEmpty ? server.id : server.kind,
      );
      if (!existingNames.contains(name)) {
        return server;
      }
    }
    return null;
  }
}

class _SettingsToolFileCard extends StatelessWidget {
  const _SettingsToolFileCard({
    required this.entry,
    required this.entries,
    required this.onSelected,
    required this.onAssign,
    required this.onCreate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ConfigFileEntry entry;
  final List<ConfigFileEntry> entries;
  final ValueChanged<ConfigFileEntry> onSelected;
  final VoidCallback? onAssign;
  final VoidCallback onCreate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Builds file selection and profile assignment controls.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Tool config file',
      children: <Widget>[
        _SettingsToolConfigDropdown(
          label: 'Config',
          entries: entries,
          selectedPath: entry.path,
          onChanged: onSelected,
        ),
        _SettingsReadOnlyField(label: 'Path', value: entry.path),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton(
              onPressed: onAssign,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      entry.assigned ? 'Assigned' : 'Use for profile',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCreate,
              tooltip: 'Add tool config',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: onDuplicate,
              tooltip: 'Duplicate tool config',
              icon: const Icon(Icons.content_copy),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete tool config',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsToolConfigDropdown extends StatelessWidget {
  const _SettingsToolConfigDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final ValueChanged<ConfigFileEntry> onChanged;

  /// Builds a filename-based selector for tool config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.fileLabel, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsLocalExecCard extends StatelessWidget {
  const _SettingsLocalExecCard({
    required this.config,
    required this.onChanged,
    required this.onAddCommand,
    required this.onDeleteCommand,
    required this.onCommandChanged,
  });

  final LocalExecToolConfig config;
  final ValueChanged<LocalExecToolConfig> onChanged;
  final VoidCallback onAddCommand;
  final ValueChanged<int> onDeleteCommand;
  final void Function(int index, LocalExecCommandConfig command)
  onCommandChanged;

  /// Builds local OS command tool settings.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Local OS tools',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: 'local_exec + request_command',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        SettingsToggleField(
          title: 'Persistent approvals',
          subtitle: 'Allow saved request_command approvals',
          value: config.allowPersistentApprovals,
          onChanged: (value) =>
              onChanged(config.copyWith(allowPersistentApprovals: value)),
        ),
        _SettingsInlineField(
          label: 'Default timeout',
          value: config.defaultTimeout,
          onChanged: (value) =>
              onChanged(config.copyWith(defaultTimeout: value)),
        ),
        _SettingsInlineField(
          label: 'Default max output bytes',
          value: config.defaultMaxOutputBytes == 0
              ? ''
              : config.defaultMaxOutputBytes.toString(),
          onChanged: (value) => onChanged(
            config.copyWith(defaultMaxOutputBytes: int.tryParse(value) ?? 0),
          ),
        ),
        _SettingsLineListField(
          label: 'Allowed workdirs',
          values: config.allowedWorkdirs,
          onChanged: (values) =>
              onChanged(config.copyWith(allowedWorkdirs: values)),
        ),
        const SizedBox(height: 4),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddCommand,
              icon: const Icon(Icons.add),
              label: const Text('Add command'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.commands.isEmpty)
          const PanelEmptyBlock(label: 'No local commands configured')
        else
          for (var index = 0; index < config.commands.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsLocalExecCommandEditor(
              command: config.commands[index],
              onDelete: () => onDeleteCommand(index),
              onChanged: (command) => onCommandChanged(index, command),
            ),
          ],
      ],
    );
  }
}

class _SettingsLocalExecCommandEditor extends StatelessWidget {
  const _SettingsLocalExecCommandEditor({
    required this.command,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecCommandConfig command;
  final ValueChanged<LocalExecCommandConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable local command alias.
  @override
  Widget build(BuildContext context) {
    final approval = command.approval;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  command.name.isEmpty ? 'Local command' : command.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete command',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: command.name,
            onChanged: (value) => onChanged(command.copyWith(name: value)),
          ),
          _SettingsInlineField(
            label: 'Executable',
            value: command.executable,
            onChanged: (value) =>
                onChanged(command.copyWith(executable: value)),
          ),
          _SettingsInlineField(
            label: 'Description',
            value: command.description,
            onChanged: (value) =>
                onChanged(command.copyWith(description: value)),
          ),
          _SettingsLineListField(
            label: 'Args',
            values: command.args,
            onChanged: (values) => onChanged(command.copyWith(args: values)),
          ),
          _SettingsInlineField(
            label: 'Timeout',
            value: command.timeout,
            onChanged: (value) => onChanged(command.copyWith(timeout: value)),
          ),
          _SettingsInlineField(
            label: 'Max output bytes',
            value: command.maxOutputBytes == 0
                ? ''
                : command.maxOutputBytes.toString(),
            onChanged: (value) => onChanged(
              command.copyWith(maxOutputBytes: int.tryParse(value) ?? 0),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow',
            subtitle: 'Skip review for this alias',
            value: approval.alwaysAllow,
            onChanged: (value) => onChanged(
              command.copyWith(approval: approval.copyWith(alwaysAllow: value)),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow within workspace',
            subtitle: 'Skip review when cwd stays in workspace',
            value: approval.alwaysAllowWithinWorkspace,
            onChanged: (value) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowWithinWorkspace: value),
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Always allow starts with',
            values: approval.alwaysAllowCommandPrefixes,
            onChanged: (values) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowCommandPrefixes: values),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMcpToolsetsCard extends StatelessWidget {
  const _SettingsMcpToolsetsCard({
    required this.config,
    required this.profileServers,
    required this.onChanged,
    required this.onAddServer,
    required this.onDeleteServer,
    required this.onServerChanged,
  });

  final McpToolConfig config;
  final List<McpServerRuntime> profileServers;
  final ValueChanged<McpToolConfig> onChanged;
  final VoidCallback onAddServer;
  final ValueChanged<int> onDeleteServer;
  final void Function(int index, McpServerToolConfig server) onServerChanged;

  /// Builds MCP server toolset settings.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'MCP toolsets',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: '${config.servers.length} configured servers',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        if (profileServers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          _SettingsProfileMcpList(servers: profileServers),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add),
              label: const Text('Add MCP server'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.servers.isEmpty)
          const PanelEmptyBlock(label: 'No MCP toolsets configured')
        else
          for (var index = 0; index < config.servers.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsMcpServerEditor(
              server: config.servers[index],
              onDelete: () => onDeleteServer(index),
              onChanged: (server) => onServerChanged(index, server),
            ),
          ],
      ],
    );
  }
}

class _SettingsProfileMcpList extends StatelessWidget {
  const _SettingsProfileMcpList({required this.servers});

  final List<McpServerRuntime> servers;

  /// Builds profile MCP endpoints that can be bridged into harness tools.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final server in servers)
            InputChip(
              avatar: const Icon(Icons.hub_outlined, size: 16),
              label: Text(server.kind.isEmpty ? server.label : server.kind),
              tooltip: server.endpoint,
              onPressed: null,
            ),
        ],
      ),
    );
  }
}

class _SettingsMcpServerEditor extends StatelessWidget {
  const _SettingsMcpServerEditor({
    required this.server,
    required this.onChanged,
    required this.onDelete,
  });

  final McpServerToolConfig server;
  final ValueChanged<McpServerToolConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable MCP server toolset.
  @override
  Widget build(BuildContext context) {
    final transport = normalizedMcpTransport(server.transport);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  server.name.isEmpty ? 'MCP server' : server.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete MCP server',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: server.name,
            onChanged: (value) => onChanged(server.copyWith(name: value)),
          ),
          _SettingsMcpTransportDropdown(
            value: transport,
            onChanged: (value) => onChanged(
              server.copyWith(
                transport: value,
                command: value == 'stdio' ? server.command : '',
                args: value == 'stdio' ? server.args : const <String>[],
                endpoint: value == 'stdio' ? '' : mcpServerEndpoint(server),
                url: '',
              ),
            ),
          ),
          if (transport == 'stdio') ...<Widget>[
            _SettingsInlineField(
              label: 'Command',
              value: server.command,
              onChanged: (value) => onChanged(server.copyWith(command: value)),
            ),
            _SettingsLineListField(
              label: 'Args',
              values: server.args,
              onChanged: (values) => onChanged(server.copyWith(args: values)),
            ),
            _SettingsKeyValueField(
              label: 'Env',
              values: server.env,
              onChanged: (values) => onChanged(server.copyWith(env: values)),
            ),
          ] else
            _SettingsInlineField(
              label: 'Endpoint',
              value: mcpServerEndpoint(server),
              onChanged: (value) =>
                  onChanged(server.copyWith(endpoint: value, url: '')),
            ),
          _SettingsLineListField(
            label: 'Allowed tools',
            values: server.tools.allow,
            onChanged: (values) => onChanged(
              server.copyWith(tools: server.tools.copyWith(allow: values)),
            ),
          ),
          SettingsToggleField(
            title: 'Require confirmation',
            subtitle: 'All tools on this server',
            value: server.requireConfirmation,
            onChanged: (value) => onChanged(
              server.copyWith(
                requireConfirmation: value,
                requireConfirmationTools: value
                    ? const <String>[]
                    : server.requireConfirmationTools,
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Require confirmation tools',
            values: server.requireConfirmationTools,
            onChanged: (values) => onChanged(
              server.copyWith(
                requireConfirmation: false,
                requireConfirmationTools: values,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMcpTransportDropdown extends StatelessWidget {
  const _SettingsMcpTransportDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds an MCP transport selector.
  @override
  Widget build(BuildContext context) {
    final selected = _mcpTransportOptions.contains(value)
        ? value
        : 'streamable-http';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'streamable-http',
            child: Text('streamable-http'),
          ),
          DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        decoration: SettingsInputDecoration.field(context, label: 'Transport'),
      ),
    );
  }
}

const List<String> _mcpTransportOptions = <String>['streamable-http', 'stdio'];

class _SettingsLineListField extends StatelessWidget {
  const _SettingsLineListField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// Builds a newline-delimited string-list field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.lines(value)),
    );
  }
}

class _SettingsKeyValueField extends StatelessWidget {
  const _SettingsKeyValueField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  /// Builds a newline-delimited KEY=value map field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.keyValues(value)),
    );
  }
}

class _SettingsToolYamlPreview extends StatelessWidget {
  const _SettingsToolYamlPreview({required this.document});

  final ToolConfigDocument document;

  /// Builds a read-only YAML preview for the structured tool config.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FormSectionCard(
      title: 'Tool config YAML',
      children: <Widget>[
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              document.toYaml(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalExecCommandDialog extends StatefulWidget {
  const _LocalExecCommandDialog();

  /// Creates state for the add-local-command dialog.
  @override
  State<_LocalExecCommandDialog> createState() =>
      _LocalExecCommandDialogState();
}

class _LocalExecCommandDialogState extends State<_LocalExecCommandDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _executable = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _executable.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Builds the required-field local command dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add command'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Name'),
            ),
            TextField(
              controller: _executable,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Executable',
              ),
            ),
            TextField(
              controller: _description,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Description',
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }

  /// Returns the new command when all required fields are present.
  void _save() {
    final name = _name.text.trim();
    final executable = _executable.text.trim();
    final description = _description.text.trim();
    if (name.isEmpty || executable.isEmpty || description.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      newLocalExecCommandConfig(
        name: name,
        executable: executable,
        description: description,
      ),
    );
  }
}

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({required this.seed});

  final McpServerRuntime? seed;

  /// Creates state for the add-MCP-server dialog.
  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final TextEditingController _name = TextEditingController(
    text: _seedName(),
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.seed?.endpoint ?? '',
  );
  final TextEditingController _command = TextEditingController();
  String _transport = 'streamable-http';

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _command.dispose();
    super.dispose();
  }

  /// Builds the required-field MCP server dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add MCP server'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _transport,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Transport',
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'streamable-http',
                  child: Text('streamable-http'),
                ),
                DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _transport = value);
                }
              },
            ),
            if (_transport == 'stdio')
              TextField(
                controller: _command,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Command',
                ),
                onSubmitted: (_) => _save(),
              )
            else
              TextField(
                controller: _endpoint,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Endpoint',
                ),
                onSubmitted: (_) => _save(),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }

  /// Returns a seed name from the runtime profile server.
  String _seedName() {
    final seed = widget.seed;
    if (seed == null) {
      return '';
    }
    return SettingsNameFactory.toolNameFromLabel(
      seed.kind.isEmpty ? seed.id : seed.kind,
    );
  }

  /// Returns the new MCP server when required fields are present.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (_transport == 'stdio') {
      final command = _command.text.trim();
      if (command.isEmpty) {
        return;
      }
      Navigator.of(
        context,
      ).pop(newStdioMcpServerToolConfig(name: name, command: command));
      return;
    }
    final endpoint = _endpoint.text.trim();
    if (endpoint.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(newHttpMcpServerToolConfig(name: name, endpoint: endpoint));
  }
}
