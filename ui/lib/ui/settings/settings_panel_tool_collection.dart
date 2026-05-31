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
  String _areaFilterId = _availableToolsAllFilter;
  String? _selectedPath;
  ToolConfigDocument? _tabDocument;
  String _tabDocumentPath = '';
  int _tabDocumentLoadToken = 0;
  Map<String, ToolConfigDocument> _availableDocuments =
      const <String, ToolConfigDocument>{};
  int _availableDocumentsLoadToken = 0;

  /// Initializes the selected tool config path.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
    unawaited(_loadTabDocument());
    unawaited(_loadAvailableDocuments());
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
    if (_entriesSignature(oldWidget) != _entriesSignature(widget)) {
      unawaited(_loadAvailableDocuments());
    }
  }

  /// Builds the fixed OS-tool or MCP-server command section.
  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.runtimeProfile;
    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
        child: _SettingsMissingRuntimePanel(section: widget.title, query: ''),
      );
    }
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: _installedToolsAreaId(widget.surface),
          title: _installedToolsAreaTitle(widget.surface),
          icon: Icons.folder_outlined,
          builder: (query) => _SettingsToolConfigFileList(
            query: query,
            entries: _entries(),
            selectedPath: _selectedPath,
            emptyLabel: _installedToolsEmptyLabel(widget.surface),
            icon: Icons.folder_outlined,
            onSelected: (path) {
              setState(() => _selectedPath = path);
              unawaited(_loadTabDocument());
            },
          ),
        ),
        SwitcherPanelArea(
          id: _availableToolsAreaId(widget.surface),
          title: _availableToolsAreaTitle(widget.surface),
          icon: Icons.travel_explore_outlined,
          builder: (query) => _SettingsAvailableToolList(
            query: query,
            filterId: _areaFilterId,
            items: _availableToolItems(),
            emptyLabel: _availableToolsEmptyLabel(widget.surface),
            onSelected: _selectAvailableTool,
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
      areaActionsBuilder: (context, area) =>
          area.id == _installedToolsAreaId(widget.surface)
          ? _buildAreaActions()
          : null,
      areaFiltersBuilder: (context, area) =>
          area.id == _availableToolsAreaId(widget.surface)
          ? _availableToolFilters()
          : const <CommandPanelFilterOption>[],
      selectedAreaFilterIdBuilder: (area) =>
          area.id == _availableToolsAreaId(widget.surface) ? _areaFilterId : '',
      onAreaFilterSelected: (area, filterId) {
        if (area.id != _availableToolsAreaId(widget.surface)) {
          return;
        }
        setState(() => _areaFilterId = filterId);
      },
      detailActionsBuilder: (context, area, mode) => _buildDetailActions(),
      areaFilterHintBuilder: (area) =>
          area.id == _availableToolsAreaId(widget.surface)
          ? 'Filter available tools...'
          : 'Filter installed files...',
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
      if (widget.surface == _ToolSettingsSurface.osTools)
        const CommandPanelDetailMode(
          id: _toolSurfaceOperationsMode,
          label: 'Operations',
          icon: Icons.account_tree_outlined,
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

  /// Returns the first available tool config path.
  String? _initialSelectedPath() {
    final entries = _entries();
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
      unawaited(_loadAvailableDocuments());
    } catch (_) {}
  }

  /// Selects the package that owns one available tool row.
  void _selectAvailableTool(_AvailableToolItem item) {
    setState(() {
      _selectedPath = item.path;
      _detailModeId = switch (item.kind) {
        _AvailableToolItemKind.operation => _toolSurfaceOperationsMode,
        _AvailableToolItemKind.command => _toolSurfaceEditMode,
        _AvailableToolItemKind.mcpServer ||
        _AvailableToolItemKind.mcpTool => _toolSurfaceEditMode,
      };
    });
    unawaited(_loadTabDocument());
  }

  /// Returns the config entries for the selected tool surface.
  List<ConfigFileEntry> _entries() {
    return widget.surface == _ToolSettingsSurface.osTools
        ? widget.controller.availableToolConfigs
        : widget.controller.availableMcpConfigs;
  }

  /// Loads every installed package document used by the available-tool index.
  Future<void> _loadAvailableDocuments() async {
    final token = ++_availableDocumentsLoadToken;
    final loaded = <String, ToolConfigDocument>{};
    for (final entry in _entries()) {
      try {
        loaded[entry.path] = ToolConfigDocument.parse(
          await widget.controller.readConfigurationFile(entry.path),
        );
      } catch (_) {}
    }
    if (!mounted || token != _availableDocumentsLoadToken) {
      return;
    }
    setState(() => _availableDocuments = loaded);
  }

  /// Builds indexed rows from installed package config documents.
  List<_AvailableToolItem> _availableToolItems() {
    final entriesByPath = <String, ConfigFileEntry>{
      for (final entry in _entries()) entry.path: entry,
    };
    final items = <_AvailableToolItem>[];
    for (final path in _availableDocuments.keys.toList()..sort()) {
      final entry = entriesByPath[path];
      final document = _availableDocuments[path];
      if (entry == null || document == null) {
        continue;
      }
      if (widget.surface == _ToolSettingsSurface.osTools) {
        items.addAll(_availableCommandItems(entry, document));
      } else {
        items.addAll(_availableMcpItems(entry, document));
      }
    }
    return items;
  }

  /// Builds quick filters for the available-tool index.
  List<CommandPanelFilterOption> _availableToolFilters() {
    final items = _availableToolItems();
    final commandCount = items
        .where((item) => item.kind == _AvailableToolItemKind.command)
        .length;
    final operationCount = items
        .where((item) => item.kind == _AvailableToolItemKind.operation)
        .length;
    final serverCount = items
        .where((item) => item.kind == _AvailableToolItemKind.mcpServer)
        .length;
    final mcpToolCount = items
        .where((item) => item.kind == _AvailableToolItemKind.mcpTool)
        .length;
    if (widget.surface == _ToolSettingsSurface.osTools) {
      return <CommandPanelFilterOption>[
        CommandPanelFilterOption(
          id: _availableToolsAllFilter,
          label: 'All',
          icon: Icons.all_inclusive,
          badge: '${items.length}',
        ),
        CommandPanelFilterOption(
          id: _availableToolsCommandsFilter,
          label: 'Commands',
          icon: Icons.terminal,
          badge: '$commandCount',
        ),
        CommandPanelFilterOption(
          id: _availableToolsOperationsFilter,
          label: 'Operations',
          icon: Icons.account_tree_outlined,
          badge: '$operationCount',
        ),
      ];
    }
    return <CommandPanelFilterOption>[
      CommandPanelFilterOption(
        id: _availableToolsAllFilter,
        label: 'All',
        icon: Icons.all_inclusive,
        badge: '${items.length}',
      ),
      CommandPanelFilterOption(
        id: _availableToolsServersFilter,
        label: 'Servers',
        icon: Icons.hub_outlined,
        badge: '$serverCount',
      ),
      CommandPanelFilterOption(
        id: _availableToolsMcpToolsFilter,
        label: 'Tools',
        icon: Icons.extension_outlined,
        badge: '$mcpToolCount',
      ),
    ];
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
      unawaited(_loadAvailableDocuments());
    } catch (_) {}
  }

  /// Deletes a tool config file after confirmation.
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
      unawaited(_loadAvailableDocuments());
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
        _availableDocuments = <String, ToolConfigDocument>{
          ..._availableDocuments,
          entry.path: document,
        };
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
      _availableDocuments = <String, ToolConfigDocument>{
        ..._availableDocuments,
        entry.path: document,
      };
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

  /// Returns a stable entry signature for installed package document reloads.
  String _entriesSignature(_SettingsToolSurfaceCommandPanel widget) {
    final entries = widget.surface == _ToolSettingsSurface.osTools
        ? widget.controller.availableToolConfigs
        : widget.controller.availableMcpConfigs;
    return entries.map((entry) => entry.path).join('\n');
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
    return PanelSelectorTile(
      label: entry.label,
      icon: icon,
      detail: entry.path,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SettingsAvailableToolList extends StatelessWidget {
  const _SettingsAvailableToolList({
    required this.query,
    required this.filterId,
    required this.items,
    required this.emptyLabel,
    required this.onSelected,
  });

  final String query;
  final String filterId;
  final List<_AvailableToolItem> items;
  final String emptyLabel;
  final ValueChanged<_AvailableToolItem> onSelected;

  /// Builds the indexed available-tool list from installed package contents.
  @override
  Widget build(BuildContext context) {
    final matches = items.where((item) {
      return _availableToolMatchesFilter(item, filterId) &&
          SettingsQuery.matches(query, item.searchTerms);
    }).toList();
    if (items.isEmpty) {
      return PanelEmptyBlock(label: emptyLabel);
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final item in matches)
          PanelSelectorTile(
            label: item.label,
            icon: item.icon,
            detail: item.detail,
            selected: false,
            onTap: () => onSelected(item),
          ),
      ],
    );
  }
}

enum _AvailableToolItemKind { command, operation, mcpServer, mcpTool }

class _AvailableToolItem {
  const _AvailableToolItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.path,
    required this.kind,
    required this.icon,
    required this.searchTerms,
  });

  final String id;
  final String label;
  final String detail;
  final String path;
  final _AvailableToolItemKind kind;
  final IconData icon;
  final List<String> searchTerms;
}

/// Builds available command and operation rows from one tool package.
List<_AvailableToolItem> _availableCommandItems(
  ConfigFileEntry entry,
  ToolConfigDocument document,
) {
  final items = <_AvailableToolItem>[];
  for (final command in document.localExec.commands) {
    final commandName = command.name.trim();
    if (commandName.isEmpty) {
      continue;
    }
    items.add(
      _AvailableToolItem(
        id: 'command:${entry.path}:$commandName',
        label: commandName,
        detail: _availableToolDetail('Command', entry, command.description),
        path: entry.path,
        kind: _AvailableToolItemKind.command,
        icon: Icons.terminal,
        searchTerms: <String>[
          commandName,
          command.description,
          command.executable,
          entry.label,
          entry.path,
          'command',
        ],
      ),
    );
    for (final operation in command.operations) {
      final operationName = operation.name.trim();
      if (operationName.isEmpty) {
        continue;
      }
      items.add(
        _AvailableToolItem(
          id: 'operation:${entry.path}:$commandName.$operationName',
          label: '$commandName.$operationName',
          detail: _availableToolDetail(
            'Operation',
            entry,
            operation.description,
          ),
          path: entry.path,
          kind: _AvailableToolItemKind.operation,
          icon: Icons.account_tree_outlined,
          searchTerms: <String>[
            commandName,
            operationName,
            '$commandName.$operationName',
            operation.description,
            entry.label,
            entry.path,
            'operation',
          ],
        ),
      );
    }
  }
  return items;
}

/// Builds available MCP server and tool rows from one MCP package.
List<_AvailableToolItem> _availableMcpItems(
  ConfigFileEntry entry,
  ToolConfigDocument document,
) {
  final items = <_AvailableToolItem>[];
  for (final server in document.mcp.servers) {
    final serverName = server.name.trim();
    if (serverName.isEmpty) {
      continue;
    }
    items.add(
      _AvailableToolItem(
        id: 'mcp-server:${entry.path}:$serverName',
        label: serverName,
        detail: _availableToolDetail(
          'MCP server',
          entry,
          mcpServerEndpoint(server),
        ),
        path: entry.path,
        kind: _AvailableToolItemKind.mcpServer,
        icon: Icons.hub_outlined,
        searchTerms: <String>[
          serverName,
          mcpServerEndpoint(server),
          entry.label,
          entry.path,
          'mcp server',
        ],
      ),
    );
    for (final tool in server.tools.allow) {
      final toolName = tool.trim();
      if (toolName.isEmpty) {
        continue;
      }
      items.add(
        _AvailableToolItem(
          id: 'mcp-tool:${entry.path}:$serverName.$toolName',
          label: toolName,
          detail: _availableToolDetail('MCP tool', entry, serverName),
          path: entry.path,
          kind: _AvailableToolItemKind.mcpTool,
          icon: Icons.extension_outlined,
          searchTerms: <String>[
            serverName,
            toolName,
            '$serverName.$toolName',
            entry.label,
            entry.path,
            'mcp tool',
          ],
        ),
      );
    }
  }
  return items;
}

/// Returns whether an available tool item matches the selected quick filter.
bool _availableToolMatchesFilter(_AvailableToolItem item, String filterId) {
  return switch (filterId) {
    _availableToolsCommandsFilter =>
      item.kind == _AvailableToolItemKind.command,
    _availableToolsOperationsFilter =>
      item.kind == _AvailableToolItemKind.operation,
    _availableToolsServersFilter =>
      item.kind == _AvailableToolItemKind.mcpServer,
    _availableToolsMcpToolsFilter =>
      item.kind == _AvailableToolItemKind.mcpTool,
    _ => true,
  };
}

/// Builds one compact detail line for an available tool row.
String _availableToolDetail(
  String kind,
  ConfigFileEntry entry,
  String description,
) {
  final parts = <String>[kind, entry.label];
  final trimmed = description.trim();
  if (trimmed.isNotEmpty) {
    parts.add(trimmed);
  }
  return parts.join(' | ');
}

/// Returns the area id for installed tool package files.
String _installedToolsAreaId(_ToolSettingsSurface surface) {
  return '${surface.id}-installed';
}

/// Returns the area id for indexed available tools.
String _availableToolsAreaId(_ToolSettingsSurface surface) {
  return '${surface.id}-available';
}

/// Returns the installed package area label.
String _installedToolsAreaTitle(_ToolSettingsSurface surface) {
  return switch (surface) {
    _ToolSettingsSurface.osTools => 'Installed Tools',
    _ToolSettingsSurface.mcpServer => 'Installed MCP Servers',
  };
}

/// Returns the indexed available package area label.
String _availableToolsAreaTitle(_ToolSettingsSurface surface) {
  return switch (surface) {
    _ToolSettingsSurface.osTools => 'Available Tools',
    _ToolSettingsSurface.mcpServer => 'Available MCP Tools',
  };
}

/// Returns the empty state label for installed package files.
String _installedToolsEmptyLabel(_ToolSettingsSurface surface) {
  return switch (surface) {
    _ToolSettingsSurface.osTools => 'No installed tool files configured',
    _ToolSettingsSurface.mcpServer =>
      'No installed MCP server files configured',
  };
}

/// Returns the empty state label for available package contents.
String _availableToolsEmptyLabel(_ToolSettingsSurface surface) {
  return switch (surface) {
    _ToolSettingsSurface.osTools => 'No available tools indexed',
    _ToolSettingsSurface.mcpServer => 'No available MCP tools indexed',
  };
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
const String _toolSurfaceOperationsMode = 'operations';
const String _toolSurfaceValidationsMode = 'validations';
const String _availableToolsAllFilter = 'all';
const String _availableToolsCommandsFilter = 'commands';
const String _availableToolsOperationsFilter = 'operations';
const String _availableToolsServersFilter = 'servers';
const String _availableToolsMcpToolsFilter = 'mcp-tools';

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
