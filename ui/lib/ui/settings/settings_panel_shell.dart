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
        label: 'Agent',
        icon: Icons.psychology_outlined,
        detail: 'Agent config and prompt policy.',
      ),
      (
        label: 'Memory',
        icon: Icons.account_tree_outlined,
        detail: 'Graph-backed memory domains.',
      ),
      (
        label: 'Tools',
        icon: Icons.tune,
        detail: 'Local OS tools and MCP toolsets.',
      ),
    ];

/// SettingsCommandSubShell renders settings in the shared command-panel shell.
class SettingsCommandSubShell extends StatelessWidget {
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
            onSelected: onSectionSelected,
          ),
        ),
      ],
      detailTitle: selected.label,
      detailModes: const <CommandPanelDetailMode>[],
      selectedDetailModeId: '',
      onDetailModeSelected: (_) {},
      detailBuilder: (_) =>
          SettingsDetailsPanel(controller: controller, section: selected.label),
      onAreaChanged: onAreaChanged,
      filterHint: 'Filter settings...',
      split: const PanelSplit(left: 0.27, min: 0.22, max: 0.42),
      showDetailHeader: false,
    );
  }

  /// Returns a valid settings section record for the selected label.
  ({String label, IconData icon, String detail}) _selectedSection() {
    for (final section in _settingsSections) {
      if (section.label == selectedSection) {
        return section;
      }
    }
    return _settingsSections.first;
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
              Icon(Icons.chevron_right, color: colors.muted),
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
  });

  final AgentAwesomeAppController controller;
  final String section;

  /// Builds the selected settings CRUD/details panel.
  @override
  Widget build(BuildContext context) {
    final profile = controller.runtimeProfile;
    if (section == 'App') {
      return _SettingsAppContent(controller: controller, profile: profile);
    }
    if (profile == null) {
      return _SettingsMissingProfilePanel(section: section);
    }
    return _buildSection(profile);
  }

  /// Builds the selected settings editor for a loaded runtime profile.
  Widget _buildSection(RuntimeProfile profile) {
    return switch (section) {
      'App' => _SettingsAppContent(controller: controller, profile: profile),
      'Profiles' => _SettingsProfilesCollection(
        controller: controller,
        profile: profile,
        profilePath: controller.runtimeProfilePath,
      ),
      'Models' => _SettingsModelProviderCollection(
        controller: controller,
        emptyLabel: 'No model configs configured',
        icon: Icons.memory_outlined,
        entries: controller.availableModelConfigs,
        assignedPath: profile.harness.modelConfigPath,
      ),
      'Agent' => _SettingsConfigFileCollection(
        controller: controller,
        title: 'Agents',
        emptyLabel: 'No agent configs configured',
        icon: Icons.psychology_outlined,
        kind: ConfigFileKind.agent,
        entries: controller.availableAgentConfigs,
        assignedPath: profile.harness.agentConfigPath,
      ),
      'Memory' => _SettingsServerContent(
        profile: profile,
        controller: controller,
        title: 'Memory Domains',
        servers: profile.memoryDomains,
      ),
      'Tools' => _SettingsToolConfigCollection(
        controller: controller,
        emptyLabel: 'No tool configs configured',
        entries: controller.availableToolConfigs,
        assignedPath: profile.harness.toolConfigPath,
      ),
      _ => _SettingsProfilesCollection(
        controller: controller,
        profile: profile,
        profilePath: controller.runtimeProfilePath,
      ),
    };
  }
}
