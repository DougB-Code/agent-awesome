/// Settings tool configuration editor widget.
part of 'settings_panel.dart';

class _SettingsToolConfigEditor extends StatefulWidget {
  const _SettingsToolConfigEditor({
    required this.controller,
    required this.entry,
    required this.surface,
    required this.modeId,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final _ToolSettingsSurface surface;
  final String modeId;
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
    if (widget.modeId == _toolSurfaceNodePresetsMode) {
      return FormPanel(
        children: <Widget>[
          _SettingsNodePresetCard(
            title: widget.surface == _ToolSettingsSurface.osTools
                ? 'Command node presets'
                : 'MCP node presets',
            presets: _surfacePresets(document),
          ),
        ],
      );
    }
    if (widget.modeId == _toolSurfaceNodeScenariosMode) {
      return FormPanel(
        children: <Widget>[
          _SettingsNodeScenarioCard(
            title: widget.surface == _ToolSettingsSurface.osTools
                ? 'Command node scenarios'
                : 'MCP node scenarios',
            scenarios: _surfaceScenarios(document),
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
        'command_execute',
        'command_template',
        for (final command in document.localExec.commands) ...<String>[
          command.name,
          command.executable,
          command.description,
          command.args.join(' '),
        ],
        for (final preset in document.nodePresets) ...<String>[
          preset.id,
          preset.label,
          preset.description,
          preset.action,
        ],
        for (final scenario in document.nodeScenarios) ...<String>[
          scenario.id,
          scenario.label,
          scenario.presetId,
          scenario.description,
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
        for (final preset in document.nodePresets) ...<String>[
          preset.id,
          preset.label,
          preset.description,
          preset.action,
        ],
        for (final scenario in document.nodeScenarios) ...<String>[
          scenario.id,
          scenario.label,
          scenario.presetId,
          scenario.description,
        ],
      ],
    };
  }

  /// Returns node presets that belong to the active settings surface.
  List<NodePresetConfig> _surfacePresets(ToolConfigDocument document) {
    final action = widget.surface == _ToolSettingsSurface.osTools
        ? 'command.execute'
        : 'mcp.call';
    return document.nodePresets
        .where((preset) => preset.action == action)
        .toList();
  }

  /// Returns node scenarios whose presets belong to the active surface.
  List<NodeScenarioConfig> _surfaceScenarios(ToolConfigDocument document) {
    final presetIds = _surfacePresets(
      document,
    ).map((preset) => preset.id).toSet();
    return document.nodeScenarios
        .where((scenario) => presetIds.contains(scenario.presetId))
        .toList();
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

class _SettingsNodePresetCard extends StatelessWidget {
  const _SettingsNodePresetCard({required this.title, required this.presets});

  final String title;
  final List<NodePresetConfig> presets;

  /// Builds installed node presets for the selected tool config.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: title,
      children: <Widget>[
        if (presets.isEmpty)
          const PanelEmptyBlock(label: 'No node presets configured')
        else
          for (var index = 0; index < presets.length; index++) ...<Widget>[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsNodePresetRow(preset: presets[index]),
          ],
      ],
    );
  }
}

class _SettingsNodePresetRow extends StatelessWidget {
  const _SettingsNodePresetRow({required this.preset});

  final NodePresetConfig preset;

  /// Builds one node preset summary row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final template = _nodeMetadataString(preset.arguments['template_id']);
    final tool = _nodeMetadataString(preset.arguments['tool']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                preset.label.isEmpty ? preset.id : preset.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            PanelBadge(label: preset.action),
          ],
        ),
        if (preset.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(preset.description, style: TextStyle(color: colors.muted)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: preset.id),
            if (template.isNotEmpty) PanelBadge(label: template),
            if (tool.isNotEmpty) PanelBadge(label: tool),
          ],
        ),
      ],
    );
  }
}

class _SettingsNodeScenarioCard extends StatelessWidget {
  const _SettingsNodeScenarioCard({
    required this.title,
    required this.scenarios,
  });

  final String title;
  final List<NodeScenarioConfig> scenarios;

  /// Builds installed node scenario metadata for the selected tool config.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: title,
      children: <Widget>[
        if (scenarios.isEmpty)
          const PanelEmptyBlock(label: 'No node scenarios configured')
        else
          for (var index = 0; index < scenarios.length; index++) ...<Widget>[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsNodeScenarioRow(scenario: scenarios[index]),
          ],
      ],
    );
  }
}

class _SettingsNodeScenarioRow extends StatelessWidget {
  const _SettingsNodeScenarioRow({required this.scenario});

  final NodeScenarioConfig scenario;

  /// Builds one node scenario summary row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    final expectedStatus = _nodeMetadataString(scenario.expected['status']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                scenario.label.isEmpty ? scenario.id : scenario.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            PanelBadge(label: scenario.live ? 'Live' : 'Mocked'),
          ],
        ),
        if (scenario.description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(scenario.description, style: TextStyle(color: colors.muted)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            PanelBadge(label: scenario.presetId),
            if (expectedStatus.isNotEmpty) PanelBadge(label: expectedStatus),
          ],
        ),
      ],
    );
  }
}

/// Converts node metadata values to concise display strings.
String _nodeMetadataString(dynamic value) {
  if (value == null) {
    return '';
  }
  return value.toString().trim();
}
