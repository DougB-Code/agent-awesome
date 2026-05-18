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
  String? _selectedMemoryDomainId;

  /// Builds the settings command panel and selected editor.
  @override
  Widget build(BuildContext context) {
    final selected = _selectedSection();
    return CommandPanelSubShell(
      areas: <SwitcherPanelArea>[
        SwitcherPanelArea(
          id: 'settings',
          title: 'Settings',
          icon: Icons.tune,
          builder: (query) => _SettingsSectionList(
            query: query,
            selected: selected.label,
            onSelected: widget.onSectionSelected,
          ),
        ),
      ],
      detailTitle: selected.label,
      detailModes: const <CommandPanelDetailMode>[],
      selectedDetailModeId: '',
      onDetailModeSelected: (_) {},
      detailBuilder: (_) => SettingsDetailsPanel(
        controller: widget.controller,
        section: selected.label,
      ),
      detailItemsBuilder: switch (selected.label) {
        'Profiles' => _profileItems,
        'Memory' => _memoryDomainItems,
        _ => null,
      },
      selectedDetailItemIdBuilder: switch (selected.label) {
        'Profiles' => _selectedProfilePathFor,
        'Memory' => _selectedMemoryDomainIdFor,
        _ => null,
      },
      onDetailItemSelected: switch (selected.label) {
        'Profiles' => (_, _, itemId) => unawaited(_selectProfile(itemId)),
        'Memory' => (_, _, itemId) => setState(
          () => _selectedMemoryDomainId = itemId,
        ),
        _ => null,
      },
      detailItemActionsBuilder: switch (selected.label) {
        'Profiles' => _profileActions,
        'Memory' => _memoryDomainActions,
        _ => null,
      },
      itemDetailBuilder:
          selected.label == 'Profiles' || selected.label == 'Memory'
          ? (_, _, item, query) => SettingsDetailsPanel(
              controller: widget.controller,
              section: selected.label,
              selectedProfilePath: selected.label == 'Profiles'
                  ? item?.id
                  : null,
              selectedMemoryDomainId: selected.label == 'Memory'
                  ? item?.id
                  : null,
              query: query,
            )
          : null,
      searchableDetailBuilder:
          selected.label == 'Profiles' || selected.label == 'Memory'
          ? null
          : (_, _, query) => SettingsDetailsPanel(
              controller: widget.controller,
              section: selected.label,
              query: query,
            ),
      onAreaChanged: widget.onAreaChanged,
      filterHint: 'Filter settings...',
      split: const PanelSplit(left: 0.27, min: 0.22, max: 0.42),
      showDetailHeader: true,
    );
  }

  /// Builds selectable runtime profiles for shared right-pane chrome.
  List<CommandPanelContentItem> _profileItems(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final profile = widget.controller.runtimeProfile;
    return <CommandPanelContentItem>[
      for (final entry in _profileEntries(profile))
        CommandPanelContentItem(
          id: entry.path,
          label: entry.label,
          detail: entry.path,
          icon: Icons.person_outline,
          badge: entry.path == widget.controller.runtimeProfilePath
              ? 'Active'
              : '',
        ),
    ];
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
          icon: Icons.add,
          tooltip: 'Add runtime profile',
          onPressed: () => unawaited(_createProfile()),
        ),
        PanelIconButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicate runtime profile',
          onPressed: item == null ? null : () => unawaited(_duplicateProfile()),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Delete runtime profile',
          onPressed: item == null ? null : () => unawaited(_deleteProfile()),
        ),
      ],
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

  /// Returns a valid settings section record for the selected label.
  ({String label, IconData icon, String detail}) _selectedSection() {
    for (final section in _settingsSections) {
      if (section.label == widget.selectedSection) {
        return section;
      }
    }
    return _settingsSections.first;
  }

  /// Builds selectable memory domains for shared right-pane chrome.
  List<CommandPanelContentItem> _memoryDomainItems(
    SwitcherPanelArea area,
    CommandPanelDetailMode mode,
  ) {
    final profile = widget.controller.runtimeProfile;
    if (profile == null) {
      return const <CommandPanelContentItem>[];
    }
    final domains = profile.memoryDomains;
    return <CommandPanelContentItem>[
      for (final server in domains)
        CommandPanelContentItem(
          id: server.id,
          label: server.label.isEmpty ? server.id : server.label,
          detail: server.endpoint,
          icon: Icons.hub_outlined,
          badge: server.enabled ? 'Enabled' : 'Disabled',
        ),
    ];
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
          icon: Icons.add,
          tooltip: 'Add memory domain',
          onPressed: () => unawaited(_createMemoryDomain()),
        ),
        PanelIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Remove memory domain',
          onPressed: item == null
              ? null
              : () => unawaited(_deleteMemoryDomain(item.id)),
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

/// _SettingsSectionList renders filtered settings section navigation.
class _SettingsSectionList extends StatelessWidget {
  const _SettingsSectionList({
    required this.query,
    required this.selected,
    required this.onSelected,
  });

  final String query;
  final String selected;
  final ValueChanged<String> onSelected;

  /// Builds the filtered settings section list.
  @override
  Widget build(BuildContext context) {
    final matches = _settingsSections.where((section) {
      return SettingsQuery.matches(query, <String>[
        section.label,
        section.detail,
      ]);
    }).toList();
    if (matches.isEmpty) {
      return PanelEmptyState(query: query);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        for (final section in matches)
          _SettingsSectionTile(
            label: section.label,
            icon: section.icon,
            detail: section.detail,
            selected: selected == section.label,
            onTap: () => onSelected(section.label),
          ),
      ],
    );
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
            children: <Widget>[
              Icon(icon, color: selected ? colors.green : colors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w900),
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
    this.selectedMemoryDomainId,
    this.query = '',
  });

  final AgentAwesomeAppController controller;
  final String section;
  final String? selectedProfilePath;
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
