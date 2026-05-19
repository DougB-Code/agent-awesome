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
      emptyLabel: 'No tool configs configured',
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
      emptyLabel: 'No MCP server tool configs configured',
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
  String _detailModeId = _toolSurfaceEditMode;
  String? _selectedPath;

  /// Initializes the selected tool config path.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
  }

  /// Keeps the selected file valid when tool config entries refresh.
  @override
  void didUpdateWidget(covariant _SettingsToolSurfaceCommandPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPath == null ||
        !widget.controller.availableToolConfigs.any(
          (entry) => entry.path == _selectedPath,
        )) {
      _selectedPath = _initialSelectedPath();
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
          title: 'Configs',
          icon: widget.icon,
          builder: (query) => _SettingsToolConfigFileList(
            query: query,
            entries: widget.controller.availableToolConfigs,
            selectedPath: _selectedPath,
            emptyLabel: widget.emptyLabel,
            icon: widget.icon,
            onSelected: (path) => setState(() => _selectedPath = path),
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
      onAreaChanged: widget.onAreaChanged,
      areaActionsBuilder: (context, area) => _buildAreaActions(),
      detailActionsBuilder: (context, area, mode) => _buildDetailActions(),
      filterHint: widget.surface == _ToolSettingsSurface.osTools
          ? 'Filter tool configs...'
          : 'Filter MCP configs...',
      split: const PanelSplit(left: 0.25, min: 0.16, max: 0.5),
    );
  }

  /// Builds the right-pane modes for the selected tool config.
  List<CommandPanelDetailMode> _detailModes() {
    return <CommandPanelDetailMode>[
      CommandPanelDetailMode(
        id: _toolSurfaceEditMode,
        label: widget.surface == _ToolSettingsSurface.osTools
            ? 'Commands'
            : 'Servers',
        icon: widget.icon,
      ),
      const CommandPanelDetailMode(
        id: _toolSurfaceSourceMode,
        label: 'Source',
        icon: Icons.code,
      ),
    ];
  }

  /// Builds collection-level controls for the config-file list.
  Widget _buildAreaActions() {
    return PanelIconButton(
      icon: Icons.add,
      tooltip: 'Add tool config',
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
          tooltip: 'Duplicate tool config',
          onPressed: selectedEntry == null
              ? null
              : () => unawaited(_duplicate(selectedEntry)),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete tool config',
          onPressed: selectedEntry == null
              ? null
              : () => unawaited(_delete(selectedEntry)),
        ),
      ],
    );
  }

  /// Builds the selected tool config editor.
  Widget _buildDetail(String modeId) {
    final entry = _selectedEntry();
    if (entry == null) {
      return _SettingsMissingToolConfig(label: widget.emptyLabel);
    }
    if (modeId == _toolSurfaceSourceMode) {
      return FormPanel(
        children: <Widget>[
          _SettingsTextFileEditor(
            controller: widget.controller,
            title: 'Tool config source',
            path: entry.path,
          ),
        ],
      );
    }
    return _SettingsToolConfigEditor(
      controller: widget.controller,
      entry: entry,
      surface: widget.surface,
      query: '',
    );
  }

  /// Returns the selected tool config entry.
  ConfigFileEntry? _selectedEntry() {
    final selectedPath = _selectedPath;
    if (selectedPath != null) {
      for (final entry in widget.controller.availableToolConfigs) {
        if (entry.path == selectedPath) {
          return entry;
        }
      }
    }
    if (widget.controller.availableToolConfigs.isEmpty) {
      return null;
    }
    return widget.controller.availableToolConfigs.first;
  }

  /// Returns the active profile assignment or first available tool config.
  String? _initialSelectedPath() {
    final entries = widget.controller.availableToolConfigs;
    final assignedPath =
        widget.controller.runtimeProfile?.harness.toolConfigPath ?? '';
    if (assignedPath.isNotEmpty &&
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
      final path = await widget.controller.createConfigFile(
        ConfigFileKind.tool,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedPath = path);
    } catch (_) {}
  }

  /// Duplicates a tool config file.
  Future<void> _duplicate(ConfigFileEntry entry) async {
    try {
      final path = await widget.controller.duplicateConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() => _selectedPath = path);
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
    } catch (_) {}
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

const String _toolSurfaceEditMode = 'edit';
const String _toolSurfaceSourceMode = 'source';

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
