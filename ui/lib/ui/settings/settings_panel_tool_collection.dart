/// Settings tool configuration collection and missing-state widgets.
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
