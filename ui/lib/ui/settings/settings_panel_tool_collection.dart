/// Settings tool configuration collection and missing-state widgets.
part of 'settings_panel.dart';

/// ToolsCommandPanel renders the dedicated OS tool configuration workspace.
class ToolsCommandPanel extends StatelessWidget {
  /// Creates the OS tools app section.
  const ToolsCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  final AgentAwesomeAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the dedicated local tool configuration command panel.
  @override
  Widget build(BuildContext context) {
    return _SettingsToolSurfaceCommandPanel(
      controller: controller,
      title: 'Tools',
      icon: Icons.terminal,
      emptyLabel: 'No tool files configured',
      surface: _ToolSettingsSurface.osTools,
      onAreaChanged: onAreaChanged,
    );
  }
}

/// McpServersCommandPanel renders the dedicated MCP server toolset workspace.
class McpServersCommandPanel extends StatelessWidget {
  /// Creates the MCP servers app section.
  const McpServersCommandPanel({
    super.key,
    required this.controller,
    this.onAreaChanged,
  });

  final AgentAwesomeAppController controller;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Builds the dedicated MCP server configuration command panel.
  @override
  Widget build(BuildContext context) {
    return _SettingsToolSurfaceCommandPanel(
      controller: controller,
      title: 'MCP Servers',
      icon: Icons.hub_outlined,
      emptyLabel: 'No MCP server files configured',
      surface: _ToolSettingsSurface.mcpServer,
      onAreaChanged: onAreaChanged,
    );
  }
}

class _SettingsToolSurfaceCommandPanel extends StatefulWidget {
  const _SettingsToolSurfaceCommandPanel({
    required this.controller,
    required this.title,
    required this.icon,
    required this.emptyLabel,
    required this.surface,
    this.onAreaChanged,
  });

  final AgentAwesomeAppController controller;
  final String title;
  final IconData icon;
  final String emptyLabel;
  final _ToolSettingsSurface surface;
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  /// Creates state for a fixed tool-surface command panel.
  @override
  State<_SettingsToolSurfaceCommandPanel> createState() =>
      _SettingsToolSurfaceCommandPanelState();
}

class _SettingsToolSurfaceCommandPanelState
    extends State<_SettingsToolSurfaceCommandPanel> {
  String _detailModeId = _toolSurfaceDetailsMode;
  String? _selectedPath;
  ToolConfigDocument? _tabDocument;
  String _tabDocumentPath = '';
  int _tabDocumentLoadToken = 0;

  /// Initializes the selected tool config path.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
    unawaited(_loadTabDocument());
  }

  /// Keeps the selected file valid when tool config entries refresh.
  @override
  void didUpdateWidget(covariant _SettingsToolSurfaceCommandPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPath == null ||
        !_entries().any((entry) => entry.path == _selectedPath)) {
      _selectedPath = _initialSelectedPath();
      unawaited(_loadTabDocument());
    }
  }

  /// Builds the fixed OS-tool or MCP-server command section.
  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.runtimeProfile;
    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
        child: _SettingsMissingProfilePanel(section: widget.title, query: ''),
      );
    }
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: widget.surface.id,
          title: widget.title,
          icon: Icons.folder_outlined,
          builder: (query) => _SettingsToolConfigFileList(
            query: query,
            entries: _entries(),
            selectedPath: _selectedPath,
            emptyLabel: widget.emptyLabel,
            icon: widget.icon,
            onSelected: (path) {
              setState(() => _selectedPath = path);
              unawaited(_loadTabDocument());
            },
          ),
        ),
      ],
      detailTitle: widget.title,
      detailModes: _detailModes(),
      selectedDetailModeId: _detailModeId,
      onDetailModeSelected: (modeId) => setState(() {
        _detailModeId = modeId;
      }),
      detailBuilder: _buildDetail,
      detailTabsBuilder: _buildDetailTabs,
      areaTabbedDetailBuilder: (area, modeId, tabId) =>
          _buildDetail(modeId, tabId: tabId),
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: (context, area) => _buildAreaActions(),
      detailActionsBuilder: (context, area, mode) => _buildDetailActions(),
      filterHint: widget.surface == _ToolSettingsSurface.osTools
          ? 'Filter tools...'
          : 'Filter MCP servers...',
      split: const PanelSplit(left: 0.30, min: 0.16, max: 0.5),
    );
  }

  /// Builds the right-pane modes for the selected tool config.
  List<CommandPanelDetailMode> _detailModes() {
    return <CommandPanelDetailMode>[
      const CommandPanelDetailMode(
        id: _toolSurfaceDetailsMode,
        label: 'Details',
        icon: Icons.info_outline,
      ),
      CommandPanelDetailMode(
        id: _toolSurfaceEditMode,
        label: widget.surface == _ToolSettingsSurface.osTools
            ? 'Commands'
            : 'Servers',
        icon: widget.icon,
      ),
      const CommandPanelDetailMode(
        id: _toolSurfaceValidationsMode,
        label: 'Validations',
        icon: Icons.fact_check_outlined,
      ),
    ];
  }

  /// Builds operation-level validation tabs for the active config file.
  List<ShellTab> _buildDetailTabs(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    if (mode.id != _toolSurfaceValidationsMode) {
      return const <ShellTab>[];
    }
    final document = _selectedTabDocument();
    if (document == null) {
      return const <ShellTab>[];
    }
    return <ShellTab>[
      for (final target in _validationTabTargets(document, widget.surface))
        ShellTab(
          id: target.id,
          label: target.label,
          icon: widget.surface == _ToolSettingsSurface.osTools
              ? Icons.terminal
              : Icons.hub_outlined,
        ),
    ];
  }

  /// Builds collection-level controls for the config-file list.
  Widget _buildAreaActions() {
    return PanelCreateButton(
      tooltip: widget.surface == _ToolSettingsSurface.osTools
          ? 'Add tool config'
          : 'Add MCP config',
      onPressed: () => unawaited(_create()),
    );
  }

  /// Builds selected-config controls in the detail header.
  Widget _buildDetailActions() {
    final selectedEntry = _selectedEntry();
    return Wrap(
      spacing: 8,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: widget.surface == _ToolSettingsSurface.osTools
              ? 'Duplicate tool config'
              : 'Duplicate MCP config',
          onPressed: selectedEntry == null
              ? null
              : () => unawaited(_duplicate(selectedEntry)),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: widget.surface == _ToolSettingsSurface.osTools
              ? 'Delete tool config'
              : 'Delete MCP config',
          onPressed: selectedEntry == null
              ? null
              : () => unawaited(_delete(selectedEntry)),
        ),
      ],
    );
  }

  /// Builds the selected tool config editor.
  Widget _buildDetail(String modeId, {String tabId = ''}) {
    final entry = _selectedEntry();
    if (entry == null) {
      return _SettingsMissingToolConfig(label: widget.emptyLabel);
    }
    return _SettingsToolConfigEditor(
      key: ValueKey<String>('${entry.path}:$modeId:$tabId'),
      controller: widget.controller,
      entry: entry,
      surface: widget.surface,
      modeId: modeId,
      validationTabId: tabId,
      query: '',
      onRenamed: (path) => _selectedPath = path,
      onDocumentChanged: _rememberTabDocument,
    );
  }

  /// Returns the selected tool config entry.
  ConfigFileEntry? _selectedEntry() {
    final selectedPath = _selectedPath;
    if (selectedPath != null) {
      for (final entry in _entries()) {
        if (entry.path == selectedPath) {
          return entry;
        }
      }
    }
    final entries = _entries();
    if (entries.isEmpty) {
      return null;
    }
    return entries.first;
  }

  /// Returns the active profile assignment or first available tool config.
  String? _initialSelectedPath() {
    final entries = _entries();
    final assignedPath =
        widget.controller.runtimeProfile?.harness.toolConfigPath ?? '';
    if (widget.surface == _ToolSettingsSurface.osTools &&
        assignedPath.isNotEmpty &&
        entries.any((entry) => entry.path == assignedPath)) {
      return assignedPath;
    }
    if (entries.isEmpty) {
      return null;
    }
    return entries.first.path;
  }

  /// Creates a new tool config file.
  Future<void> _create() async {
    try {
      final path = await widget.controller.createConfigFile(_configKind());
      if (!mounted) {
        return;
      }
      setState(() => _selectedPath = path);
      unawaited(_loadTabDocument());
    } catch (_) {}
  }

  /// Returns the config entries for the selected tool surface.
  List<ConfigFileEntry> _entries() {
    return widget.surface == _ToolSettingsSurface.osTools
        ? widget.controller.availableToolConfigs
        : widget.controller.availableMcpConfigs;
  }

  /// Returns the config file kind owned by the selected tool surface.
  ConfigFileKind _configKind() {
    return widget.surface == _ToolSettingsSurface.osTools
        ? ConfigFileKind.tool
        : ConfigFileKind.mcp;
  }

  /// Duplicates a tool config file.
  Future<void> _duplicate(ConfigFileEntry entry) async {
    try {
      final path = await widget.controller.duplicateConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() => _selectedPath = path);
      unawaited(_loadTabDocument());
    } catch (_) {}
  }

  /// Deletes an unassigned tool config file after confirmation.
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
      setState(() => _selectedPath = _initialSelectedPath());
      unawaited(_loadTabDocument());
    } catch (_) {}
  }

  /// Loads the selected config document for validation tab construction.
  Future<void> _loadTabDocument() async {
    final entry = _selectedEntry();
    final token = ++_tabDocumentLoadToken;
    if (entry == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tabDocument = null;
        _tabDocumentPath = '';
      });
      return;
    }
    try {
      final content = await widget.controller.readConfigurationFile(entry.path);
      final document = ToolConfigDocument.parse(content);
      if (!mounted || token != _tabDocumentLoadToken) {
        return;
      }
      setState(() {
        _tabDocument = document;
        _tabDocumentPath = entry.path;
      });
    } catch (_) {
      if (!mounted || token != _tabDocumentLoadToken) {
        return;
      }
      setState(() {
        _tabDocument = null;
        _tabDocumentPath = '';
      });
    }
  }

  /// Remembers the latest selected document emitted by the active editor.
  void _rememberTabDocument(ToolConfigDocument document) {
    final entry = _selectedEntry();
    if (entry == null) {
      return;
    }
    setState(() {
      _tabDocument = document;
      _tabDocumentPath = entry.path;
    });
  }

  /// Returns the selected document only when it belongs to the selected file.
  ToolConfigDocument? _selectedTabDocument() {
    final entry = _selectedEntry();
    if (entry == null || _tabDocumentPath != entry.path) {
      return null;
    }
    return _tabDocument;
  }
}

class _SettingsToolConfigFileList extends StatelessWidget {
  const _SettingsToolConfigFileList({
    required this.query,
    required this.entries,
    required this.selectedPath,
    required this.emptyLabel,
    required this.icon,
    required this.onSelected,
  });

  final String query;
  final List<ConfigFileEntry> entries;
  final String? selectedPath;
  final String emptyLabel;
  final IconData icon;
  final ValueChanged<String> onSelected;

  /// Builds the left file-browser list for tool config files.
  @override
  Widget build(BuildContext context) {
    final matches = entries.where((entry) {
      return SettingsQuery.matches(query, <String>[
        entry.label,
        entry.fileLabel,
        entry.path,
        if (entry.assigned) 'assigned',
      ]);
    }).toList();
    if (entries.isEmpty) {
      return PanelEmptyBlock(label: emptyLabel);
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final entry in matches)
          _SettingsToolConfigFileTile(
            entry: entry,
            icon: icon,
            selected: entry.path == selectedPath,
            onTap: () => onSelected(entry.path),
          ),
      ],
    );
  }
}

class _SettingsToolConfigFileTile extends StatelessWidget {
  const _SettingsToolConfigFileTile({
    required this.entry,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ConfigFileEntry entry;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Builds one selectable tool config file row.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: PanelSurface(
          fillWidth: true,
          padding: const EdgeInsets.all(12),
          style: PanelSurfaceStyle.card,
          selected: selected,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: selected ? colors.green : colors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted),
                    ),
                    if (entry.assigned) ...<Widget>[
                      const SizedBox(height: 8),
                      const PanelBadge(label: 'Assigned'),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
}

class _ToolValidationTabTarget {
  /// Creates one operation or MCP-tool verification tab target.
  const _ToolValidationTabTarget({required this.id, required this.label});

  /// Stable tab id used to match validations.
  final String id;

  /// Human-facing tab label.
  final String label;
}

/// Returns configured validation targets used as right-pane verification tabs.
List<_ToolValidationTabTarget> _validationTabTargets(
  ToolConfigDocument document,
  _ToolSettingsSurface surface,
) {
  final targets = <_ToolValidationTabTarget>[];
  final seen = <String>{};
  if (surface == _ToolSettingsSurface.osTools) {
    for (final command in document.localExec.commands) {
      final commandName = command.name.trim();
      for (final operation in command.operations) {
        final operationName = operation.name.trim();
        if (commandName.isEmpty || operationName.isEmpty) {
          continue;
        }
        final id = _commandValidationTabId(commandName, operationName);
        if (seen.add(id)) {
          targets.add(_ToolValidationTabTarget(id: id, label: operationName));
        }
      }
    }
  } else {
    for (final server in document.mcp.servers) {
      final serverName = server.name.trim();
      for (final tool in server.tools.allow) {
        final toolName = tool.trim();
        if (serverName.isEmpty || toolName.isEmpty) {
          continue;
        }
        final id = _mcpValidationTabId(serverName, toolName);
        if (seen.add(id)) {
          targets.add(_ToolValidationTabTarget(id: id, label: toolName));
        }
      }
    }
  }
  if (targets.isNotEmpty) {
    return targets;
  }
  for (final validation in document.validations) {
    final target = validation.target;
    final id = _validationTabIdForTarget(target);
    if (id.isEmpty || !seen.add(id)) {
      continue;
    }
    targets.add(
      _ToolValidationTabTarget(
        id: id,
        label: _validationTargetLabel(target).split('.').last,
      ),
    );
  }
  return targets;
}

/// Returns whether one validation belongs to a validation target tab.
bool _validationConfigMatchesTab(
  ToolValidationConfig validation,
  String tabId,
) {
  final selected = tabId.trim();
  return selected.isEmpty ||
      _validationTabIdForTarget(validation.target) == selected;
}

/// Returns the tab id for a command operation validation target.
String _commandValidationTabId(String command, String operation) {
  return 'command:${command.trim()}.${operation.trim()}';
}

/// Returns the tab id for an MCP tool validation target.
String _mcpValidationTabId(String server, String tool) {
  return 'mcp:${server.trim()}.${tool.trim()}';
}

/// Returns the tab id for a validation target.
String _validationTabIdForTarget(ToolValidationTargetConfig target) {
  if (target.command.isNotEmpty && target.operation.isNotEmpty) {
    return _commandValidationTabId(target.command, target.operation);
  }
  if (target.mcpServer.isNotEmpty && target.mcpTool.isNotEmpty) {
    return _mcpValidationTabId(target.mcpServer, target.mcpTool);
  }
  return '';
}

const String _toolSurfaceEditMode = 'edit';
const String _toolSurfaceDetailsMode = 'details';
const String _toolSurfaceValidationsMode = 'validations';

class _SettingsMissingToolConfig extends StatelessWidget {
  const _SettingsMissingToolConfig({required this.label});

  final String label;

  /// Builds the empty state shown before a tool config file exists.
  @override
  Widget build(BuildContext context) {
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          title: 'Tool config',
          children: <Widget>[PanelEmptyBlock(label: label)],
        ),
      ],
    );
  }
}
