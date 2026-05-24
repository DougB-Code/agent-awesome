/// Settings shell navigation and section routing widgets.
part of 'settings_panel.dart';

const List<({String label, IconData icon, String detail})> _settingsSections =
    <({String label, IconData icon, String detail})>[
      (
        label: 'App',
        icon: Icons.dashboard_customize_outlined,
        detail: 'Chat defaults and app-owned model choices.',
      ),
      (
        label: 'Profiles',
        icon: Icons.person_outline,
        detail: 'Runtime topology and active profile.',
      ),
      (
        label: 'Models',
        icon: Icons.memory_outlined,
        detail: 'Model config and harness runtime.',
      ),
      (
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
  String? _selectedProfilePath;
  String? _selectedModelConfigPath;
  String? _selectedMemoryDomainId;

  /// Builds the settings command panel and selected editor.
  @override
  Widget build(BuildContext context) {
    return CommandPanelSubShell(
      areas: _settingsAreas(),
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
      searchableDetailBuilder: _buildAreaDetail,
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
          id: section.label,
          title: section.label,
          icon: section.icon,
          builder: (query) => _SettingsAreaContent(
            controller: widget.controller,
            section: section.label,
            detail: section.detail,
            query: query,
            selectedProfilePath: _selectedProfilePathForArea(),
            selectedModelConfigPath: _selectedModelConfigPathForArea(),
            selectedMemoryDomainId: _selectedMemoryDomainIdForArea(),
            onProfileSelected: (path) => unawaited(_selectProfile(path)),
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
    return <CommandPanelDetailMode>[
      CommandPanelDetailMode(
        id: area.id,
        label: 'Details',
        icon: Icons.info_outline,
      ),
    ];
  }

  /// Builds the active settings editor for the selected left area.
  Widget _buildAreaDetail(SwitcherPanelArea area, String modeId, String query) {
    return SettingsDetailsPanel(
      controller: widget.controller,
      section: area.id,
      selectedProfilePath: area.id == 'Profiles'
          ? _selectedProfilePathForArea()
          : null,
      selectedModelConfigPath: area.id == 'Models'
          ? _selectedModelConfigPathForArea()
          : null,
      onModelConfigSelected: area.id == 'Models'
          ? (path) => setState(() => _selectedModelConfigPath = path)
          : null,
      selectedMemoryDomainId: area.id == 'Memory'
          ? _selectedMemoryDomainIdForArea()
          : null,
      query: query,
    );
  }

  /// Builds selected-object actions for settings areas.
  Widget? _buildDetailActions(
    BuildContext context,
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    return switch (area.id) {
      'Profiles' => _profileActions(context, area, mode, null),
      'Models' => _modelConfigActions(context, area, mode),
      'Memory' => _memoryDomainActions(context, area, mode, null),
      _ => null,
    };
  }

  /// Builds collection-level settings actions in the left header.
  Widget? _buildAreaActions(BuildContext context, SwitcherPanelArea area) {
    return switch (area.id) {
      'Profiles' => PanelIconButton(
        icon: Icons.add,
        tooltip: 'Add runtime profile',
        onPressed: () => unawaited(_createProfile()),
      ),
      'Models' => PanelIconButton(
        icon: Icons.add,
        tooltip: 'Add model config',
        onPressed: () => unawaited(_createModelConfig()),
      ),
      'Memory' => PanelIconButton(
        icon: Icons.add,
        tooltip: 'Add memory domain',
        onPressed: () => unawaited(_createMemoryDomain()),
      ),
      _ => null,
    };
  }

  /// Resolves the selected runtime profile path for the shared detail selector.
  String? _selectedProfilePathFor(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final entries = _profileEntries(widget.controller.runtimeProfile);
    if (entries.isEmpty) {
      return null;
    }
    final selected = _selectedProfilePath;
    if (selected != null && entries.any((entry) => entry.path == selected)) {
      return selected;
    }
    final activePath = widget.controller.runtimeProfilePath;
    if (activePath.isNotEmpty &&
        entries.any((entry) => entry.path == activePath)) {
      return activePath;
    }
    return entries.first.path;
  }

  /// Resolves the selected runtime profile path for left-area content.
  String? _selectedProfilePathForArea() {
    return _selectedProfilePathFor(
      const SwitcherPanelArea(
        id: 'Profiles',
        title: 'Profiles',
        icon: Icons.person_outline,
        builder: _emptySettingsAreaBuilder,
      ),
      const CommandPanelDetailMode(
        id: 'Profiles',
        label: 'Profiles',
        icon: Icons.person_outline,
      ),
    );
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

  /// Builds profile-file CRUD controls in the shared detail header.
  Widget _profileActions(
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
          tooltip: 'Duplicate runtime profile',
          onPressed: _selectedProfilePathForArea() == null
              ? null
              : () => unawaited(_duplicateProfile()),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete runtime profile',
          onPressed: _selectedProfilePathForArea() == null
              ? null
              : () => unawaited(_deleteProfile()),
        ),
      ],
    );
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

  /// Returns profile choices, including the active profile when needed.
  List<RuntimeProfileFileEntry> _profileEntries(RuntimeProfile? profile) {
    if (widget.controller.availableProfiles.isNotEmpty) {
      return widget.controller.availableProfiles;
    }
    if (profile == null || widget.controller.runtimeProfilePath.isEmpty) {
      return const <RuntimeProfileFileEntry>[];
    }
    return <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: widget.controller.runtimeProfilePath,
        id: profile.id,
        label: profile.label,
        active: true,
      ),
    ];
  }

  /// Loads a runtime profile selected through shared right-pane chrome.
  Future<void> _selectProfile(String path) async {
    try {
      setState(() => _selectedProfilePath = path);
      await widget.controller.loadRuntimeProfileFromPath(path);
    } catch (_) {}
  }

  /// Creates a runtime profile and selects it through shared chrome.
  Future<void> _createProfile() async {
    try {
      await widget.controller.createRuntimeProfileFile();
      if (!mounted) {
        return;
      }
      setState(
        () => _selectedProfilePath = widget.controller.runtimeProfilePath,
      );
    } catch (_) {}
  }

  /// Duplicates the active runtime profile and selects the duplicate.
  Future<void> _duplicateProfile() async {
    try {
      await widget.controller.duplicateRuntimeProfileFile();
      if (!mounted) {
        return;
      }
      setState(
        () => _selectedProfilePath = widget.controller.runtimeProfilePath,
      );
    } catch (_) {}
  }

  /// Confirms and deletes the active runtime profile.
  Future<void> _deleteProfile() async {
    final profilePath = widget.controller.runtimeProfilePath;
    if (profilePath.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: SettingsConfigLabels.fileLabel(profilePath),
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteActiveRuntimeProfileFile();
      if (!mounted) {
        return;
      }
      setState(
        () => _selectedProfilePath = widget.controller.runtimeProfilePath,
      );
    } catch (_) {}
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

  /// Confirms and deletes a memory domain from the active profile.
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
    final label = server.label.trim().isEmpty ? server.id : server.label;
    final confirmed = await _confirmSettingsDelete(
      context,
      label: label,
      message:
          'Delete "$label" from this profile? Existing files at ${server.dbPath} and ${server.dataDir} are not removed automatically.',
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

/// _SettingsAreaContent renders the selected settings area context list.
class _SettingsAreaContent extends StatelessWidget {
  const _SettingsAreaContent({
    required this.controller,
    required this.section,
    required this.detail,
    required this.query,
    required this.selectedProfilePath,
    required this.selectedModelConfigPath,
    required this.selectedMemoryDomainId,
    required this.onProfileSelected,
    required this.onModelConfigSelected,
    required this.onMemoryDomainSelected,
  });

  final AgentAwesomeAppController controller;
  final String section;
  final String detail;
  final String query;
  final String? selectedProfilePath;
  final String? selectedModelConfigPath;
  final String? selectedMemoryDomainId;
  final ValueChanged<String> onProfileSelected;
  final ValueChanged<String> onModelConfigSelected;
  final ValueChanged<String> onMemoryDomainSelected;

  /// Builds area-specific supporting objects for Settings.
  @override
  Widget build(BuildContext context) {
    return switch (section) {
      'Profiles' => _buildProfiles(),
      'Models' => _buildModels(),
      'Memory' => _buildMemoryDomains(),
      _ => _buildSingleAppItem(),
    };
  }

  Widget _buildSingleAppItem() {
    if (!SettingsQuery.matches(query, <String>['App', detail])) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _SettingsSectionTile(
          label: 'App settings',
          icon: Icons.dashboard_customize_outlined,
          detail: detail,
          selected: true,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildProfiles() {
    final entries = _profileAreaEntries();
    final matches = entries.where((entry) {
      return SettingsQuery.matches(query, <String>[
        entry.label,
        entry.id,
        entry.path,
        if (entry.active) 'active',
      ]);
    }).toList();
    if (entries.isEmpty) {
      return const PanelEmptyBlock(label: 'No runtime profiles configured');
    }
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final entry in matches)
          _SettingsSectionTile(
            label: entry.label,
            icon: Icons.person_outline,
            detail: entry.path,
            selected: entry.path == selectedProfilePath,
            onTap: () => onProfileSelected(entry.path),
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
          _SettingsSectionTile(
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
        domain.id,
        domain.label,
        domain.endpoint,
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
          _SettingsSectionTile(
            label: domain.label.isEmpty ? domain.id : domain.label,
            icon: Icons.hub_outlined,
            detail: domain.endpoint,
            selected: domain.id == selectedMemoryDomainId,
            onTap: () => onMemoryDomainSelected(domain.id),
          ),
      ],
    );
  }

  List<RuntimeProfileFileEntry> _profileAreaEntries() {
    if (controller.availableProfiles.isNotEmpty) {
      return controller.availableProfiles;
    }
    final profile = controller.runtimeProfile;
    if (profile == null || controller.runtimeProfilePath.isEmpty) {
      return const <RuntimeProfileFileEntry>[];
    }
    return <RuntimeProfileFileEntry>[
      RuntimeProfileFileEntry(
        path: controller.runtimeProfilePath,
        id: profile.id,
        label: profile.label,
        active: true,
      ),
    ];
  }
}

/// _SettingsSectionTile renders one settings section picker row.
class _SettingsSectionTile extends StatelessWidget {
  const _SettingsSectionTile({
    required this.label,
    required this.icon,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  /// Builds a compact command-panel navigation tile.
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
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted),
                    ),
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

/// SettingsDetailsPanel renders the selected settings section editor.
class SettingsDetailsPanel extends StatelessWidget {
  /// Creates a settings details panel bound to the app controller.
  const SettingsDetailsPanel({
    super.key,
    required this.controller,
    required this.section,
    this.selectedProfilePath,
    this.selectedModelConfigPath,
    this.onModelConfigSelected,
    this.selectedMemoryDomainId,
    this.query = '',
  });

  final AgentAwesomeAppController controller;
  final String section;
  final String? selectedProfilePath;
  final String? selectedModelConfigPath;
  final ValueChanged<String>? onModelConfigSelected;
  final String? selectedMemoryDomainId;
  final String query;

  /// Builds the selected settings CRUD/details panel.
  @override
  Widget build(BuildContext context) {
    final profile = controller.runtimeProfile;
    if (section == 'App') {
      return _SettingsAppContent(
        controller: controller,
        profile: profile,
        query: query,
      );
    }
    if (profile == null) {
      return _SettingsMissingProfilePanel(section: section, query: query);
    }
    return _buildSection(profile);
  }

  /// Builds the selected settings editor for a loaded runtime profile.
  Widget _buildSection(RuntimeProfile profile) {
    return switch (section) {
      'App' => _SettingsAppContent(
        controller: controller,
        profile: profile,
        query: query,
      ),
      'Profiles' => _SettingsProfilesCollection(
        controller: controller,
        profile: profile,
        profilePath: selectedProfilePath ?? controller.runtimeProfilePath,
        query: query,
      ),
      'Models' => _SettingsModelProviderCollection(
        controller: controller,
        emptyLabel: 'No model configs configured',
        icon: Icons.memory_outlined,
        entries: controller.availableModelConfigs,
        assignedPath: profile.harness.modelConfigPath,
        selectedPath: selectedModelConfigPath,
        onSelectedPathChanged: onModelConfigSelected,
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
      _ => _SettingsProfilesCollection(
        controller: controller,
        profile: profile,
        profilePath: controller.runtimeProfilePath,
        query: query,
      ),
    };
  }
}
