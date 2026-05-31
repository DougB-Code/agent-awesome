/// Settings shell navigation and section routing widgets.
part of 'settings_panel.dart';

const List<({String id, String label, IconData icon, String detail})>
_settingsSections = <({String id, String label, IconData icon, String detail})>[
  (
    id: 'App',
    label: 'App',
    icon: Icons.dashboard_customize_outlined,
    detail: 'Chat defaults and app-owned model choices.',
  ),
  (
    id: 'Models',
    label: 'Models',
    icon: Icons.memory_outlined,
    detail: 'Model providers, endpoints, and compatibility validations.',
  ),
  (
    id: 'Memory',
    label: 'Memory',
    icon: Icons.account_tree_outlined,
    detail: 'Graph-backed memory domains.',
  ),
];

/// SettingsCommandSubShell renders settings in the shared command-panel shell.
class SettingsCommandSubShell extends StatefulWidget {
  /// Creates a command-style settings workspace.
  const SettingsCommandSubShell({
    super.key,
    required this.controller,
    required this.selectedSection,
    required this.onSectionSelected,
    this.onAreaChanged,
  });

  /// Shared app controller.
  final AgentAwesomeAppController controller;

  /// Currently selected settings section.
  final String selectedSection;

  /// Selects a settings section from the navigation panel.
  final ValueChanged<String> onSectionSelected;

  /// Reports the active command area to the app shell.
  final ValueChanged<SwitcherPanelArea>? onAreaChanged;

  @override
  State<SettingsCommandSubShell> createState() =>
      _SettingsCommandSubShellState();
}

class _SettingsCommandSubShellState extends State<SettingsCommandSubShell> {
  String? _selectedModelConfigPath;
  String? _selectedMemoryDomainId;
  final Map<String, String> _selectedDetailModeIds = <String, String>{};

  /// Builds the settings command panel and selected editor.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _settingsAreas(),
      selectedAreaId: widget.selectedSection,
      detailTitle: 'Settings',
      detailModes: const <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: 'settings',
          label: 'Details',
          icon: Icons.info_outline,
        ),
      ],
      detailModesBuilder: _detailModesForArea,
      selectedDetailModeId: '',
      onDetailModeSelected: (_) {},
      detailBuilder: (_) =>
          SettingsDetailsPanel(controller: widget.controller, section: 'App'),
      areaDetailBuilder: _buildAreaDetail,
      selectedDetailModeIdBuilder: _selectedDetailModeIdForArea,
      onAreaDetailModeSelected: _selectDetailModeForArea,
      areaActionsBuilder: _buildAreaActions,
      detailActionsBuilder: _buildDetailActions,
      onAreaChanged: (area) {
        widget.onSectionSelected(area.id);
        widget.onAreaChanged?.call(area);
      },
      filterHint: 'Filter settings...',
      split: const PanelSplit(left: 0.27, min: 0.22, max: 0.42),
      showDetailHeader: true,
    );
  }

  /// Builds shell-owned settings section areas.
  List<SwitcherPanelArea> _settingsAreas() {
    return <SwitcherPanelArea>[
      for (final section in _settingsSections)
        SwitcherPanelArea(
          id: section.id,
          title: section.label,
          icon: section.icon,
          builder: (query) => _SettingsAreaContent(
            controller: widget.controller,
            section: section.id,
            detail: section.detail,
            query: query,
            selectedModelConfigPath: _selectedModelConfigPathForArea(),
            selectedMemoryDomainId: _selectedMemoryDomainIdForArea(),
            onModelConfigSelected: (path) =>
                setState(() => _selectedModelConfigPath = path),
            onMemoryDomainSelected: (domainId) =>
                setState(() => _selectedMemoryDomainId = domainId),
          ),
        ),
    ];
  }

  /// Returns the single right-side settings mode for one left area.
  List<CommandPanelDetailMode> _detailModesForArea(SwitcherPanelArea area) {
    if (area.id == 'Models') {
      return <CommandPanelDetailMode>[
        CommandPanelDetailMode(
          id: area.id,
          label: 'Details',
          icon: Icons.info_outline,
        ),
        const CommandPanelDetailMode(
          id: 'model-validations',
          label: 'Validations',
          icon: Icons.fact_check_outlined,
        ),
      ];
    }
    return <CommandPanelDetailMode>[
      CommandPanelDetailMode(
        id: area.id,
        label: 'Details',
        icon: Icons.info_outline,
      ),
    ];
  }

  /// Resolves the selected right-pane mode for one settings area.
  String _selectedDetailModeIdForArea(SwitcherPanelArea area) {
    final selected = _selectedDetailModeIds[area.id];
    final modes = _detailModesForArea(area);
    if (selected != null && modes.any((mode) => mode.id == selected)) {
      return selected;
    }
    return modes.isEmpty ? '' : modes.first.id;
  }

  /// Stores the selected right-pane mode for one settings area.
  void _selectDetailModeForArea(SwitcherPanelArea area, String modeId) {
    setState(() => _selectedDetailModeIds[area.id] = modeId);
  }

  /// Builds the active settings editor for the selected left area.
  Widget _buildAreaDetail(SwitcherPanelArea area, String modeId) {
    return SettingsDetailsPanel(
      controller: widget.controller,
      section: area.id,
      selectedModelConfigPath: area.id == 'Models'
          ? _selectedModelConfigPathForArea()
          : null,
      onModelConfigSelected: area.id == 'Models'
          ? (path) => setState(() => _selectedModelConfigPath = path)
          : null,
      selectedMemoryDomainId: area.id == 'Memory'
          ? _selectedMemoryDomainIdForArea()
          : null,
      modeId: modeId,
    );
  }

  /// Builds selected-object actions for settings areas.
  Widget? _buildDetailActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    return switch (area.id) {
      'Models' => _modelConfigActions(context, area, mode),
      'Memory' => _memoryDomainActions(context, area, mode, null),
      _ => null,
    };
  }

  /// Builds collection-level settings actions in the left header.
  Widget? _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    if (area.id == 'Models') {
      return PanelCreateButton(
        tooltip: 'Add model config',
        onPressed: () => unawaited(_createModelConfig()),
      );
    }
    if (area.id == 'Memory') {
      return PanelIconButton(
        icon: Icons.add,
        tooltip: 'Add memory domain',
        onPressed: () => unawaited(_showMemoryDomainCreateMenu(context)),
      );
    }
    return null;
  }

  /// Resolves the selected model config path for left-area content.
  String? _selectedModelConfigPathForArea() {
    final entries = widget.controller.availableModelConfigs;
    if (entries.isEmpty) {
      return null;
    }
    final selectedPath = _selectedModelConfigPath;
    if (selectedPath != null &&
        entries.any((entry) => entry.path == selectedPath)) {
      return selectedPath;
    }
    final assignedPath =
        widget.controller.runtimeProfile?.harness.modelConfigPath ?? '';
    if (assignedPath.isNotEmpty &&
        entries.any((entry) => entry.path == assignedPath)) {
      return assignedPath;
    }
    return entries.first.path;
  }

  /// Builds selected model-config controls in the right header.
  Widget _modelConfigActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final entry = _selectedModelConfigEntry();
    return Wrap(
      spacing: 8,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicate model config',
          onPressed: entry == null
              ? null
              : () => unawaited(_duplicateModelConfig(entry)),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete model config',
          onPressed: entry == null
              ? null
              : () => unawaited(_deleteModelConfig(entry)),
        ),
      ],
    );
  }

  /// Returns the selected model config entry, if one exists.
  ConfigFileEntry? _selectedModelConfigEntry() {
    final selectedPath = _selectedModelConfigPathForArea();
    if (selectedPath == null) {
      return null;
    }
    for (final entry in widget.controller.availableModelConfigs) {
      if (entry.path == selectedPath) {
        return entry;
      }
    }
    return null;
  }

  /// Creates a model config and selects it in the left area.
  Future<void> _createModelConfig() async {
    try {
      final path = await widget.controller.createConfigFile(
        ConfigFileKind.model,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedModelConfigPath = path);
    } catch (_) {}
  }

  /// Duplicates the selected model config and selects the duplicate.
  Future<void> _duplicateModelConfig(ConfigFileEntry entry) async {
    try {
      final path = await widget.controller.duplicateConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() => _selectedModelConfigPath = path);
    } catch (_) {}
  }

  /// Deletes the selected model config after confirmation.
  Future<void> _deleteModelConfig(ConfigFileEntry entry) async {
    final confirmed = await _confirmSettingsDelete(context, label: entry.label);
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(
        () => _selectedModelConfigPath = _selectedModelConfigPathForArea(),
      );
    } catch (_) {}
  }

  /// Resolves the selected memory-domain id for left-area content.
  String? _selectedMemoryDomainIdForArea() {
    return _selectedMemoryDomainIdFor(
      const SwitcherPanelArea(
        id: 'Memory',
        title: 'Memory',
        icon: Icons.account_tree_outlined,
        builder: _emptySettingsAreaBuilder,
      ),
      const CommandPanelDetailMode(
        id: 'Memory',
        label: 'Memory',
        icon: Icons.account_tree_outlined,
      ),
    );
  }

  /// Resolves the selected memory-domain id without section-owned chrome.
  String? _selectedMemoryDomainIdFor(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final profile = widget.controller.runtimeProfile;
    if (profile == null) {
      return null;
    }
    final selectedId = _selectedMemoryDomainId;
    if (selectedId != null &&
        profile.memoryDomains.any((domain) => domain.id == selectedId)) {
      return selectedId;
    }
    return _initialMemoryDomainId(profile);
  }

  /// Builds memory-domain CRUD controls in the shared detail header.
  Widget _memoryDomainActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
    CommandPanelContentItem? item,
  ) {
    return Wrap(
      spacing: 8,
      children: <Widget>[
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicate memory domain',
          onPressed: _selectedMemoryDomainIdForArea() == null
              ? null
              : () => unawaited(
                  _duplicateMemoryDomain(_selectedMemoryDomainIdForArea()!),
                ),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Remove memory domain',
          onPressed: _selectedMemoryDomainIdForArea() == null
              ? null
              : () => unawaited(
                  _deleteMemoryDomain(_selectedMemoryDomainIdForArea()!),
                ),
        ),
      ],
    );
  }

  /// Returns the default selected memory-domain id.
  String? _initialMemoryDomainId(RuntimeProfile profile) {
    if (profile.memoryDomains.isEmpty) {
      return null;
    }
    for (final domain in profile.memoryDomains) {
      if (domain.id == profile.agentMemory.defaultWriteDomain) {
        return domain.id;
      }
    }
    return profile.memoryDomains.first.id;
  }

  /// Creates a memory domain and selects it in the shared right-pane shell.
  Future<void> _createMemoryDomain() async {
    try {
      final domain = await widget.controller.createMemoryDomainRuntime();
      if (!mounted) {
        return;
      }
      setState(() => _selectedMemoryDomainId = domain.id);
    } catch (_) {}
  }

  /// Lets the user choose whether to add a local or cloud memory domain.
  Future<void> _showMemoryDomainCreateMenu(BuildContext context) async {
    final choice = await showDialog<_MemoryDomainCreateChoice>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Add memory domain'),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_MemoryDomainCreateChoice.local),
              child: const ListTile(
                leading: Icon(Icons.storage_outlined),
                title: Text('Local memory'),
                subtitle: Text('Add a domain in the local memory pool.'),
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_MemoryDomainCreateChoice.cloud),
              child: const ListTile(
                leading: Icon(Icons.cloud_outlined),
                title: Text('Cloud memory'),
                subtitle: Text('Connect an external MCP endpoint.'),
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || choice == null) {
      return;
    }
    switch (choice) {
      case _MemoryDomainCreateChoice.local:
        await _createMemoryDomain();
      case _MemoryDomainCreateChoice.cloud:
        await _createExternalMemoryDomain();
    }
  }

  /// Creates an externally hosted memory domain from typed dialog fields.
  Future<void> _createExternalMemoryDomain() async {
    final request = await _promptExternalMemoryDomain();
    if (request == null) {
      return;
    }
    try {
      final domain = await widget.controller.createExternalMemoryDomainRuntime(
        label: request.label,
        endpoint: request.endpoint,
        healthUrl: request.healthUrl,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedMemoryDomainId = domain.id);
    } catch (_) {}
  }

  /// Prompts for the display name and URLs used by an external memory domain.
  Future<_ExternalMemoryDomainRequest?> _promptExternalMemoryDomain() async {
    final name = TextEditingController(text: 'Cloud Memory');
    final endpoint = TextEditingController(text: 'https://example.com/mcp');
    final health = TextEditingController();
    try {
      return await showDialog<_ExternalMemoryDomainRequest>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Cloud memory'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PanelLabeledFormControl(
                      label: 'Name',
                      child: TextField(
                        controller: name,
                        autofocus: true,
                        style: SettingsFormTextStyle.field(dialogContext),
                        decoration: SettingsInputDecoration.field(
                          dialogContext,
                          label: 'Name',
                        ),
                      ),
                    ),
                    const SizedBox(height: SettingsFormMetrics.fieldGap),
                    PanelLabeledFormControl(
                      label: 'MCP endpoint',
                      child: TextField(
                        controller: endpoint,
                        keyboardType: TextInputType.url,
                        style: SettingsFormTextStyle.field(dialogContext),
                        decoration: SettingsInputDecoration.field(
                          dialogContext,
                          label: 'MCP endpoint',
                        ),
                      ),
                    ),
                    const SizedBox(height: SettingsFormMetrics.fieldGap),
                    PanelLabeledFormControl(
                      label: 'Health URL',
                      child: TextField(
                        controller: health,
                        keyboardType: TextInputType.url,
                        style: SettingsFormTextStyle.field(dialogContext),
                        decoration: SettingsInputDecoration.field(
                          dialogContext,
                          label: 'Health URL',
                          hintText: 'Optional',
                        ),
                        onSubmitted: (_) => Navigator.of(dialogContext).pop(
                          _ExternalMemoryDomainRequest(
                            label: name.text.trim(),
                            endpoint: endpoint.text.trim(),
                            healthUrl: health.text.trim(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _ExternalMemoryDomainRequest(
                    label: name.text.trim(),
                    endpoint: endpoint.text.trim(),
                    healthUrl: health.text.trim(),
                  ),
                ),
                child: const Text('Connect'),
              ),
            ],
          );
        },
      );
    } finally {
      name.dispose();
      endpoint.dispose();
      health.dispose();
    }
  }

  /// Duplicates a memory domain and selects the duplicate.
  Future<void> _duplicateMemoryDomain(String domainId) async {
    try {
      final domain = await widget.controller.duplicateMemoryDomainRuntime(
        domainId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectedMemoryDomainId = domain.id);
    } catch (_) {}
  }

  /// Confirms and deletes a memory domain from the managed runtime.
  Future<void> _deleteMemoryDomain(String domainId) async {
    final profile = widget.controller.runtimeProfile;
    if (profile == null) {
      return;
    }
    McpServerRuntime? server;
    for (final candidate in profile.memoryDomains) {
      if (candidate.id == domainId) {
        server = candidate;
        break;
      }
    }
    if (server == null) {
      return;
    }
    final name = _memoryDomainDisplayName(server);
    final confirmed = await _confirmSettingsDelete(
      context,
      label: name,
      message:
          'Delete "$name"? Local data files are not removed automatically.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteMemoryDomainRuntime(server.id);
      if (!mounted) {
        return;
      }
      setState(() {
        final nextProfile = widget.controller.runtimeProfile;
        _selectedMemoryDomainId = nextProfile == null
            ? null
            : _initialMemoryDomainId(nextProfile);
      });
    } catch (_) {}
  }
}

/// Builds an empty placeholder for const shell-area references.
Widget _emptySettingsAreaBuilder(String query) {
  return const SizedBox.shrink();
}

/// _MemoryDomainCreateChoice identifies the memory domain setup path.
enum _MemoryDomainCreateChoice {
  /// Create and manage a local graph-backed memory server.
  local,

  /// Connect an externally hosted MCP memory endpoint.
  cloud,
}

/// _ExternalMemoryDomainRequest stores typed external memory setup input.
class _ExternalMemoryDomainRequest {
  const _ExternalMemoryDomainRequest({
    required this.label,
    required this.endpoint,
    required this.healthUrl,
  });

  /// User-facing memory domain label.
  final String label;

  /// Streamable HTTP MCP endpoint.
  final String endpoint;

  /// Optional HTTP health-check URL.
  final String healthUrl;
}

/// _SettingsAreaContent renders the selected settings area context list.
class _SettingsAreaContent extends StatelessWidget {
  const _SettingsAreaContent({
    required this.controller,
    required this.section,
    required this.detail,
    required this.query,
    required this.selectedModelConfigPath,
    required this.selectedMemoryDomainId,
    required this.onModelConfigSelected,
    required this.onMemoryDomainSelected,
  });

  final AgentAwesomeAppController controller;
  final String section;
  final String detail;
  final String query;
  final String? selectedModelConfigPath;
  final String? selectedMemoryDomainId;
  final ValueChanged<String> onModelConfigSelected;
  final ValueChanged<String> onMemoryDomainSelected;

  /// Builds area-specific supporting objects for Settings.
  @override
  Widget build(BuildContext context) {
    return switch (section) {
      'Models' => _buildModels(),
      'Memory' => _buildMemoryDomains(),
      _ => _buildSingleAppItem(),
    };
  }

  /// Builds the singleton app settings selector row.
  Widget _buildSingleAppItem() {
    if (!SettingsQuery.matches(query, <String>[
      'App',
      'App settings',
      detail,
    ])) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        PanelSelectorTile(
          label: 'App settings',
          icon: Icons.dashboard_customize_outlined,
          detail: detail,
          selected: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildModels() {
    final matches = controller.availableModelConfigs.where((entry) {
      return SettingsQuery.matches(query, <String>[
        entry.label,
        entry.fileLabel,
        entry.path,
        if (entry.assigned) 'assigned',
      ]);
    }).toList();
    if (controller.availableModelConfigs.isEmpty) {
      return const PanelEmptyBlock(label: 'No model configs configured');
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final entry in matches)
          PanelSelectorTile(
            label: entry.label,
            icon: Icons.memory_outlined,
            detail: entry.path,
            selected: entry.path == selectedModelConfigPath,
            onTap: () => onModelConfigSelected(entry.path),
          ),
      ],
    );
  }

  Widget _buildMemoryDomains() {
    final domains = controller.runtimeProfile?.memoryDomains ?? const [];
    final matches = domains.where((domain) {
      return SettingsQuery.matches(query, <String>[
        domain.label,
        _memoryDomainDisplayName(domain),
        'memory domain',
        if (domain.autoStart) 'auto-start' else 'external',
        if (domain.enabled) 'enabled' else 'disabled',
      ]);
    }).toList();
    if (domains.isEmpty) {
      return const PanelEmptyBlock(label: 'No memory domains configured');
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final domain in matches)
          PanelSelectorTile(
            label: _memoryDomainDisplayName(domain),
            icon: Icons.hub_outlined,
            detail: _memoryDomainStateLabel(domain),
            selected: domain.id == selectedMemoryDomainId,
            onTap: () => onMemoryDomainSelected(domain.id),
          ),
      ],
    );
  }
}

/// Returns the user-facing memory domain name without exposing internal ids.
String _memoryDomainDisplayName(McpServerRuntime domain) {
  final name = domain.label.trim();
  return name.isEmpty ? 'Memory domain' : name;
}

/// Returns a compact user-facing status summary for a memory domain.
String _memoryDomainStateLabel(McpServerRuntime domain) {
  final enabled = domain.enabled ? 'Enabled' : 'Disabled';
  final startup = domain.autoStart ? 'Auto-start' : 'External';
  return '$enabled, $startup';
}

/// SettingsDetailsPanel renders the selected settings section editor.
class SettingsDetailsPanel extends StatelessWidget {
  /// Creates a settings details panel bound to the app controller.
  const SettingsDetailsPanel({
    super.key,
    required this.controller,
    required this.section,
    this.selectedModelConfigPath,
    this.onModelConfigSelected,
    this.selectedMemoryDomainId,
    this.modeId = '',
    this.query = '',
  });

  final AgentAwesomeAppController controller;
  final String section;
  final String? selectedModelConfigPath;
  final ValueChanged<String>? onModelConfigSelected;
  final String? selectedMemoryDomainId;
  final String modeId;
  final String query;

  /// Builds the selected settings CRUD/details panel.
  @override
  Widget build(BuildContext context) {
    final profile = controller.runtimeProfile;
    if (section == 'App') {
      return _SettingsAppContent(controller: controller, query: query);
    }
    if (profile == null) {
      return _SettingsMissingRuntimePanel(section: section, query: query);
    }
    return _buildSection(profile);
  }

  /// Builds the selected settings editor for a loaded managed runtime.
  Widget _buildSection(RuntimeProfile profile) {
    return switch (section) {
      'App' => _SettingsAppContent(controller: controller, query: query),
      'Models' => _SettingsModelProviderCollection(
        controller: controller,
        emptyLabel: 'No model configs configured',
        icon: Icons.memory_outlined,
        entries: controller.availableModelConfigs,
        assignedPath: profile.harness.modelConfigPath,
        selectedPath: selectedModelConfigPath,
        onSelectedPathChanged: onModelConfigSelected,
        modeId: modeId,
        query: query,
      ),
      'Memory' => _SettingsServerContent(
        profile: profile,
        controller: controller,
        title: 'Memory Domains',
        servers: profile.memoryDomains,
        selectedServerId: selectedMemoryDomainId,
        query: query,
      ),
      _ => _SettingsAppContent(controller: controller, query: query),
    };
  }
}

/// _SettingsMissingRuntimePanel renders settings unavailable without services.
class _SettingsMissingRuntimePanel extends StatelessWidget {
  /// Creates a missing-runtime placeholder for settings sections.
  const _SettingsMissingRuntimePanel({
    required this.section,
    required this.query,
  });

  /// Settings section that requested runtime-backed data.
  final String section;

  /// Active settings filter text.
  final String query;

  /// Builds the missing-runtime empty state.
  @override
  Widget build(BuildContext context) {
    if (!SettingsQuery.matches(query, <String>[
      section,
      'Agent Awesome runtime unavailable',
    ])) {
      return PanelEmptyState(query: query);
    }
    return const FormPanel(
      children: <Widget>[
        PanelEmptyBlock(label: 'Agent Awesome runtime unavailable'),
      ],
    );
  }
}
