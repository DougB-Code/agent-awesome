/// Settings tool configuration editor widget.
part of 'settings_panel.dart';

class _SettingsToolConfigEditor extends StatefulWidget {
  const _SettingsToolConfigEditor({
    required this.controller,
    required this.entry,
    required this.surface,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final _ToolSettingsSurface surface;
  final String query;

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
