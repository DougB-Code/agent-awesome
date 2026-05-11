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
        detail: 'Graph-backed knowledge MCP binding.',
      ),
      (
        label: 'Tools',
        icon: Icons.tune,
        detail: 'Local OS tools and MCP toolsets.',
      ),
    ];

/// SettingsMenuPanel renders the left settings section navigation.
class SettingsMenuPanel extends StatelessWidget {
  /// Creates a settings section navigation panel.
  const SettingsMenuPanel({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  /// Builds the settings sub-menu picker.
  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      title: 'Settings',
      subtitle: 'App defaults, profiles, models, memory, and tools.',
      selectedKey: selected,
      onSelected: onSelected,
      items: <MenuPanelItem>[
        for (final section in _settingsSections)
          MenuPanelItem(
            key: section.label,
            label: section.label,
            icon: section.icon,
            detail: section.detail,
          ),
      ],
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
        title: 'Memory',
        servers: profile.memoryServers,
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
