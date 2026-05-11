/// Implements the settings workspace panels for Agent Awesome configuration.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/config_files.dart';
import '../../app/credential_store.dart';
import '../../app/runtime_profile.dart';
import '../../app/theme.dart';
import '../../app/tool_config.dart';
import '../../domain/model_config.dart';
import '../panels/panels.dart';
import 'settings_form.dart';
import 'settings_logic.dart';

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

class _SettingsAppContent extends StatefulWidget {
  const _SettingsAppContent({required this.controller, required this.profile});

  final AgentAwesomeAppController controller;
  final RuntimeProfile? profile;

  /// Creates state for app-specific settings edits.
  @override
  State<_SettingsAppContent> createState() => _SettingsAppContentState();
}

class _SettingsAppContentState extends State<_SettingsAppContent> {
  final SettingsSaveFeedbackController _profileFeedback =
      SettingsSaveFeedbackController();
  final SettingsSaveFeedbackController _summaryToggleFeedback =
      SettingsSaveFeedbackController();
  final SettingsSaveFeedbackController _summaryModelFeedback =
      SettingsSaveFeedbackController();

  /// Cleans up save feedback controllers.
  @override
  void dispose() {
    _profileFeedback.dispose();
    _summaryToggleFeedback.dispose();
    _summaryModelFeedback.dispose();
    super.dispose();
  }

  /// Builds app-owned settings that are intentionally outside profiles.
  @override
  Widget build(BuildContext context) {
    final profiles = _profileEntries();
    return CollectionSwitcherPanel<String>(
      title: 'App',
      selectedId: 'app-settings',
      emptyLabel: 'No app settings configured',
      items: const <CollectionPanelItem<String>>[
        CollectionPanelItem<String>(
          id: 'app-settings',
          label: 'App Settings',
          detail: 'Chat defaults and app-owned model choices.',
          icon: Icons.dashboard_customize_outlined,
          value: 'app-settings',
        ),
      ],
      onSelect: (_) {},
      builder: (_, query) => _buildAppSettings(query, profiles),
    );
  }

  /// Builds the combined app settings surface.
  Widget _buildAppSettings(
    String query,
    List<RuntimeProfileFileEntry> profiles,
  ) {
    if (!SettingsQuery.matches(query, <String>[
      'Chat Defaults',
      'Default profile',
      widget.controller.defaultChatProfilePath,
      'Application Models',
      'Generate chat titles',
      'Summary model',
      widget.controller.summaryModelConfigPath,
      widget.controller.summaryModelRef,
      for (final profile in profiles) ...<String>[
        profile.label,
        profile.id,
        profile.path,
      ],
      for (final entry in widget.controller.availableModelConfigs) ...<String>[
        entry.label,
        entry.path,
        for (final choice in entry.modelChoices) choice.label,
      ],
    ])) {
      return PanelEmptyState(query: query);
    }
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          children: <Widget>[
            SettingsFormSubsection(
              title: 'Chat defaults',
              children: <Widget>[
                SettingsSaveFeedback(
                  controller: _profileFeedback,
                  child: _SettingsProfileDropdown(
                    label: 'Default profile',
                    entries: profiles,
                    selectedPath: widget.controller.defaultChatProfilePath,
                    onChanged: _setDefaultProfile,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SettingsFormMetrics.sectionGap),
            SettingsFormSubsection(
              title: 'Application models',
              children: <Widget>[
                SettingsToggleField(
                  title: 'Generate chat titles',
                  subtitle: 'Summarize titles with a model.',
                  value:
                      widget.controller.appSettings.chatTitleSummariesEnabled,
                  onChanged: (value) => unawaited(_setSummaryEnabled(value)),
                ),
                SettingsSaveFeedback(
                  controller: _summaryModelFeedback,
                  child: _SettingsSummaryModelDropdown(
                    label: 'Summary model',
                    entries: widget.controller.availableModelConfigs,
                    selectedPath: widget.controller.summaryModelConfigPath,
                    selectedModelRef: widget.controller.summaryModelRef,
                    onChanged: _setSummaryModel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Returns profile choices, including the active profile path when needed.
  List<RuntimeProfileFileEntry> _profileEntries() {
    if (widget.controller.availableProfiles.isNotEmpty) {
      return widget.controller.availableProfiles;
    }
    final profile = widget.profile;
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

  /// Persists the default profile selected for new chats.
  Future<void> _setDefaultProfile(RuntimeProfileFileEntry entry) async {
    await _profileFeedback.run(() {
      return widget.controller.setDefaultChatProfile(entry.path);
    });
  }

  /// Persists the exact app-owned summary model selection.
  Future<void> _setSummaryModel(_SummaryModelOption option) async {
    await _summaryModelFeedback.run(() {
      return widget.controller.setSummaryModelSelection(
        modelConfigPath: option.configPath,
        modelRef: option.modelRef,
      );
    });
  }

  /// Persists whether app-owned title summaries are enabled.
  Future<void> _setSummaryEnabled(bool enabled) async {
    await _summaryToggleFeedback.run(() {
      return widget.controller.setChatTitleSummariesEnabled(enabled);
    });
  }
}

class _SettingsMissingProfilePanel extends StatelessWidget {
  const _SettingsMissingProfilePanel({required this.section});

  final String section;

  /// Builds a high-density settings panel for missing profile state.
  @override
  Widget build(BuildContext context) {
    return CollectionSwitcherPanel<String>(
      title: section,
      selectedId: 'missing-profile',
      emptyLabel: 'Runtime profile unavailable',
      items: const <CollectionPanelItem<String>>[
        CollectionPanelItem<String>(
          id: 'missing-profile',
          label: 'Profile Required',
          icon: Icons.warning_amber_outlined,
          value: 'missing-profile',
        ),
      ],
      onSelect: (_) {},
      builder: (_, query) {
        if (!SettingsQuery.matches(query, <String>[
          section,
          'Profile Required',
        ])) {
          return PanelEmptyState(query: query);
        }
        return const _RuntimeProfileMissing();
      },
    );
  }
}

class _RuntimeProfileMissing extends StatelessWidget {
  const _RuntimeProfileMissing();

  /// Builds the profile configuration error state.
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: PanelEmptyBlock(label: 'Runtime profile unavailable'),
    );
  }
}

class _SettingsProfilesCollection extends StatefulWidget {
  const _SettingsProfilesCollection({
    required this.controller,
    required this.profile,
    required this.profilePath,
  });

  final AgentAwesomeAppController controller;
  final RuntimeProfile profile;
  final String profilePath;

  @override
  State<_SettingsProfilesCollection> createState() =>
      _SettingsProfilesCollectionState();
}

class _SettingsProfilesCollectionState
    extends State<_SettingsProfilesCollection> {
  /// Builds a file-backed runtime profile collection panel.
  @override
  Widget build(BuildContext context) {
    final profiles = widget.controller.availableProfiles.isEmpty
        ? <RuntimeProfileFileEntry>[
            RuntimeProfileFileEntry(
              path: widget.profilePath,
              id: widget.profile.id,
              label: widget.profile.label,
              active: true,
            ),
          ]
        : widget.controller.availableProfiles;
    return CollectionSwitcherPanel<RuntimeProfileFileEntry>(
      title: 'Profiles',
      selectedId: widget.profilePath,
      emptyLabel: 'No profiles configured',
      items: <CollectionPanelItem<RuntimeProfileFileEntry>>[
        for (final entry in profiles)
          CollectionPanelItem<RuntimeProfileFileEntry>(
            id: entry.path,
            label: entry.label,
            detail: entry.path,
            icon: Icons.person_outline,
            badge: entry.path == widget.profilePath ? 'Active' : '',
            value: entry,
          ),
      ],
      onSelect: (path) => unawaited(_load(path)),
      onCreate: () => unawaited(_create()),
      onDuplicate: (_) => unawaited(_duplicate()),
      onDelete: (_) => unawaited(_delete()),
      builder: (entry, query) {
        return _SettingsProfileEditor(
          controller: widget.controller,
          profile: widget.profile,
          profilePath: entry.path,
          query: query,
        );
      },
    );
  }

  Future<void> _load(String path) async {
    try {
      await widget.controller.loadRuntimeProfileFromPath(path);
    } catch (_) {}
  }

  Future<void> _create() async {
    try {
      await widget.controller.createRuntimeProfileFile();
    } catch (_) {}
  }

  Future<void> _duplicate() async {
    try {
      await widget.controller.duplicateRuntimeProfileFile();
    } catch (_) {}
  }

  Future<void> _delete() async {
    final confirmed = await _confirmSettingsDelete(
      context,
      label: SettingsConfigLabels.fileLabel(widget.profilePath),
    );
    if (!confirmed) {
      return;
    }
    try {
      await widget.controller.deleteActiveRuntimeProfileFile();
    } catch (_) {}
  }
}

class _SettingsProfileEditor extends StatefulWidget {
  const _SettingsProfileEditor({
    required this.controller,
    required this.profile,
    required this.profilePath,
    required this.query,
  });

  final AgentAwesomeAppController controller;
  final RuntimeProfile profile;
  final String profilePath;
  final String query;

  @override
  State<_SettingsProfileEditor> createState() => _SettingsProfileEditorState();
}

class _SettingsProfileEditorState extends State<_SettingsProfileEditor> {
  late final TextEditingController _label = TextEditingController(
    text: widget.profile.label,
  );
  String _savedLabel = '';

  /// Initializes profile editor state.
  @override
  void initState() {
    super.initState();
    _savedLabel = widget.profile.label;
  }

  /// Cleans up profile form controllers.
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Synchronizes controllers when a different profile is loaded.
  @override
  void didUpdateWidget(covariant _SettingsProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.label != widget.profile.label) {
      _label.text = widget.profile.label;
      _savedLabel = widget.profile.label;
    }
  }

  /// Builds active profile details from the loaded JSON profile.
  @override
  Widget build(BuildContext context) {
    if (!SettingsQuery.matches(widget.query, <String>[
      widget.profile.label,
      widget.profilePath,
    ])) {
      return PanelEmptyState(query: widget.query);
    }
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          title: 'Details',
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Name',
              controller: _label,
              initialSavedValue: _savedLabel,
              onSave: _saveLabel,
            ),
            _SettingsReadOnlyField(
              label: 'JSON source',
              value: widget.profilePath,
            ),
          ],
        ),
        FormSectionCard(
          title: 'Assignments',
          children: <Widget>[
            _SettingsConfigDropdown(
              label: 'Model',
              entries: widget.controller.availableModelConfigs,
              selectedPath: widget.profile.harness.modelConfigPath,
              onChanged: _assignConfig,
            ),
            _SettingsConfigDropdown(
              label: 'Agent',
              entries: widget.controller.availableAgentConfigs,
              selectedPath: widget.profile.harness.agentConfigPath,
              onChanged: _assignConfig,
            ),
            _SettingsConfigDropdown(
              label: 'Tools',
              entries: widget.controller.availableToolConfigs,
              selectedPath: widget.profile.harness.toolConfigPath,
              onChanged: _assignConfig,
            ),
            _SettingsMcpServerAssignmentDropdown(
              label: 'Memory',
              kind: 'memory',
              servers: widget.profile.mcpServers,
              onChanged: _assignMcpServer,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _saveLabel(String value) async {
    final next = widget.profile.copyWith(label: value.trim());
    try {
      await widget.controller.saveRuntimeProfile(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedLabel = value.trim();
      });
    } catch (_) {}
  }

  /// Assigns a selected config file to this profile.
  Future<void> _assignConfig(ConfigFileEntry entry) async {
    try {
      await widget.controller.assignConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Enables the selected MCP server for its required profile role.
  Future<void> _assignMcpServer(McpServerRuntime selected) async {
    try {
      await widget.controller.assignMcpServerForKind(selected);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }
}

class _SettingsModelProviderCollection extends StatefulWidget {
  const _SettingsModelProviderCollection({
    required this.controller,
    required this.emptyLabel,
    required this.icon,
    required this.entries,
    required this.assignedPath,
  });

  final AgentAwesomeAppController controller;
  final String emptyLabel;
  final IconData icon;
  final List<ConfigFileEntry> entries;
  final String assignedPath;

  @override
  State<_SettingsModelProviderCollection> createState() =>
      _SettingsModelProviderCollectionState();
}

class _SettingsModelProviderCollectionState
    extends State<_SettingsModelProviderCollection> {
  String? _selectedPath;
  String? _selectedProviderId;
  ModelConfigDocument? _document;
  bool _loading = true;

  /// Initializes the selected model config and provider.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
    unawaited(_load());
  }

  /// Keeps the selected model config valid when config files refresh.
  @override
  void didUpdateWidget(covariant _SettingsModelProviderCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedPath = _selectedPath;
    if (selectedPath == null ||
        !widget.entries.any((entry) => entry.path == selectedPath)) {
      _selectedPath = _initialSelectedPath();
      _document = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds the provider-centric model settings panel.
  @override
  Widget build(BuildContext context) {
    final entry = _selectedEntry();
    final document = _document;
    final providers = document?.providers ?? const <ModelProviderConfig>[];
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return CollectionSwitcherPanel<ModelProviderConfig>(
      title: 'Models',
      selectedId: _selectedProviderIdFor(providers),
      emptyLabel: entry == null ? widget.emptyLabel : 'No providers configured',
      items: <CollectionPanelItem<ModelProviderConfig>>[
        for (final provider in providers)
          CollectionPanelItem<ModelProviderConfig>(
            id: provider.id,
            label: provider.displayName,
            detail: provider.id,
            icon: widget.icon,
            badge: _isDefaultProvider(document, provider.id) ? 'Active' : '',
            value: provider,
          ),
      ],
      onSelect: (id) => setState(() => _selectedProviderId = id),
      onCreate: () => unawaited(_addProvider()),
      onDuplicate: (provider) => unawaited(_duplicateProvider(provider)),
      onDelete: (provider) => unawaited(_deleteProvider(provider)),
      builder: (provider, query) {
        if (entry == null || document == null) {
          return PanelEmptyState(query: query);
        }
        return _buildProviderEditor(entry, document, provider, query);
      },
    );
  }

  Widget _buildProviderEditor(
    ConfigFileEntry entry,
    ModelConfigDocument document,
    ModelProviderConfig provider,
    String query,
  ) {
    if (!SettingsQuery.matches(query, <String>[
      provider.id,
      provider.name,
      provider.adapter,
      provider.apiKey,
      provider.url,
      for (final model in provider.models) ...<String>[model.id, model.model],
    ])) {
      return PanelEmptyState(query: query);
    }
    return FormPanel(
      children: <Widget>[
        _SettingsActionRow(
          children: <Widget>[
            FilledButton.icon(
              onPressed: entry.assigned
                  ? null
                  : () => unawaited(_assign(entry)),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(entry.assigned ? 'Assigned' : 'Use for profile'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _isDefaultProvider(document, provider.id)
                  ? null
                  : () => unawaited(
                      _setDefaultProvider(entry, document, provider),
                    ),
              icon: const Icon(Icons.radio_button_checked),
              label: Text(
                _isDefaultProvider(document, provider.id)
                    ? 'Default provider'
                    : 'Set default provider',
              ),
            ),
          ],
        ),
        _SettingsModelProviderCard(
          controller: widget.controller,
          provider: provider,
          onChanged: (next) => _replaceProvider(document, provider.id, next),
        ),
        _SettingsModelProviderYamlPreview(provider: provider),
      ],
    );
  }

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

  ConfigFileEntry? _selectedEntry() {
    final selectedPath = _selectedPath;
    if (selectedPath != null) {
      for (final entry in widget.entries) {
        if (entry.path == selectedPath) {
          return entry;
        }
      }
      return ConfigFileEntry(
        path: selectedPath,
        kind: ConfigFileKind.model,
        assigned: selectedPath == widget.assignedPath,
      );
    }
    if (widget.entries.isEmpty) {
      return null;
    }
    return widget.entries.first;
  }

  String? _selectedProviderIdFor(List<ModelProviderConfig> providers) {
    if (providers.isEmpty) {
      return null;
    }
    final selected = _selectedProviderId;
    if (selected != null &&
        providers.any((provider) => provider.id == selected)) {
      return selected;
    }
    final defaultProviderId = _defaultProviderId(_document);
    if (defaultProviderId.isNotEmpty &&
        providers.any((provider) => provider.id == defaultProviderId)) {
      return defaultProviderId;
    }
    return providers.first.id;
  }

  Future<void> _load() async {
    final entry = _selectedEntry();
    if (entry == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _document = null;
        _loading = false;
      });
      return;
    }
    try {
      final content = await widget.controller.readConfigurationFile(entry.path);
      final document = ModelConfigDocument.parse(content);
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _selectedProviderId = _selectedProviderIdFor(document.providers);
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

  Future<void> _addProvider() async {
    var entry = _selectedEntry();
    if (entry == null) {
      try {
        final path = await widget.controller.createConfigFile(
          ConfigFileKind.model,
        );
        await widget.controller.refreshConfigurationCollections();
        if (!mounted) {
          return;
        }
        setState(() {
          _selectedPath = path;
          _loading = true;
        });
        await _load();
        entry = _selectedEntry();
      } catch (_) {
        return;
      }
    }
    if (entry == null) {
      return;
    }
    final document =
        _document ?? const ModelConfigDocument(defaultRef: '', providers: []);
    final nextId = SettingsConfigIds.uniqueProviderId(document, 'provider');
    final provider = newModelProviderConfig(nextId);
    final defaultRef = document.defaultRef.trim().isEmpty
        ? '${provider.id}:${provider.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(
        defaultRef: defaultRef,
        providers: <ModelProviderConfig>[...document.providers, provider],
      ),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _duplicateProvider(ModelProviderConfig provider) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    final nextId = SettingsConfigIds.uniqueProviderId(
      document,
      '${provider.id}-copy',
    );
    final nextProvider = provider.copyWith(
      id: nextId,
      name: '${provider.displayName} Copy',
    );
    await _saveDocument(
      entry,
      document.copyWith(
        providers: <ModelProviderConfig>[...document.providers, nextProvider],
      ),
      selectedProviderId: nextProvider.id,
    );
  }

  Future<void> _deleteProvider(ModelProviderConfig provider) async {
    final entry = _selectedEntry();
    final document = _document;
    if (entry == null || document == null) {
      return;
    }
    if (document.providers.length <= 1) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: provider.displayName,
    );
    if (!confirmed) {
      return;
    }
    if (provider.apiKey.trim().isNotEmpty) {
      await widget.controller.deleteCredential(provider.apiKey);
    }
    final providers = document.providers
        .where((candidate) => candidate.id != provider.id)
        .toList();
    final deletingDefault = _isDefaultProvider(document, provider.id);
    final defaultRef = deletingDefault
        ? '${providers.first.id}:${providers.first.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: defaultRef, providers: providers),
      selectedProviderId: deletingDefault
          ? providers.first.id
          : _selectedProviderIdFor(providers) ?? providers.first.id,
    );
  }

  Future<void> _replaceProvider(
    ModelConfigDocument document,
    String previousId,
    ModelProviderConfig provider,
  ) async {
    final entry = _selectedEntry();
    if (entry == null) {
      return;
    }
    final duplicate = document.providers.any((candidate) {
      return candidate.id == provider.id && candidate.id != previousId;
    });
    if (duplicate) {
      return;
    }
    final providers = <ModelProviderConfig>[
      for (final candidate in document.providers)
        candidate.id == previousId ? provider : candidate,
    ];
    final defaultRef = document.defaultRef.startsWith('$previousId:')
        ? '${provider.id}:${provider.defaultModel}'
        : document.defaultRef;
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: defaultRef, providers: providers),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _assign(ConfigFileEntry entry) async {
    try {
      await widget.controller.assignConfigFile(entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Marks the selected provider as the config-level default provider.
  Future<void> _setDefaultProvider(
    ConfigFileEntry entry,
    ModelConfigDocument document,
    ModelProviderConfig provider,
  ) async {
    await _saveDocument(
      entry,
      document.copyWith(defaultRef: modelProviderDefaultRef(provider)),
      selectedProviderId: provider.id,
    );
  }

  Future<void> _saveDocument(
    ConfigFileEntry entry,
    ModelConfigDocument document, {
    required String selectedProviderId,
  }) async {
    final validationError = modelConfigValidationError(document);
    if (validationError.isNotEmpty) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(
        entry.path,
        document.toYaml(),
      );
      await widget.controller.refreshConfigurationCollections();
      if (!mounted) {
        return;
      }
      setState(() {
        _document = document;
        _selectedProviderId = selectedProviderId;
      });
    } catch (_) {}
  }

  bool _isDefaultProvider(ModelConfigDocument? document, String providerId) {
    return _defaultProviderId(document) == providerId;
  }

  String _defaultProviderId(ModelConfigDocument? document) {
    return document?.defaultRef.split(':').first.trim() ?? '';
  }
}

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

class _SettingsToolConfigEditor extends StatefulWidget {
  const _SettingsToolConfigEditor({
    required this.controller,
    required this.entry,
    required this.entries,
    required this.surface,
    required this.query,
    required this.onConfigSelected,
    required this.onCreateConfig,
    required this.onDuplicateConfig,
    required this.onDeleteConfig,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final List<ConfigFileEntry> entries;
  final _ToolSettingsSurface surface;
  final String query;
  final ValueChanged<ConfigFileEntry> onConfigSelected;
  final VoidCallback onCreateConfig;
  final VoidCallback onDuplicateConfig;
  final VoidCallback onDeleteConfig;

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
    return FormPanel(
      children: <Widget>[
        _SettingsToolFileCard(
          entry: widget.entry,
          entries: widget.entries,
          onSelected: widget.onConfigSelected,
          onAssign: widget.entry.assigned ? null : _assign,
          onCreate: widget.onCreateConfig,
          onDuplicate: widget.onDuplicateConfig,
          onDelete: widget.onDeleteConfig,
        ),
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
        _SettingsToolYamlPreview(document: document),
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
        'local_exec',
        'request_command',
        for (final command in document.localExec.commands) ...<String>[
          command.name,
          command.executable,
          command.description,
          command.args.join(' '),
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
      ],
    };
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

  /// Assigns the selected tool config file to the active profile.
  Future<void> _assign() async {
    try {
      await widget.controller.assignConfigFile(widget.entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
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

class _SettingsToolFileCard extends StatelessWidget {
  const _SettingsToolFileCard({
    required this.entry,
    required this.entries,
    required this.onSelected,
    required this.onAssign,
    required this.onCreate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ConfigFileEntry entry;
  final List<ConfigFileEntry> entries;
  final ValueChanged<ConfigFileEntry> onSelected;
  final VoidCallback? onAssign;
  final VoidCallback onCreate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Builds file selection and profile assignment controls.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Tool config file',
      children: <Widget>[
        _SettingsToolConfigDropdown(
          label: 'Config',
          entries: entries,
          selectedPath: entry.path,
          onChanged: onSelected,
        ),
        _SettingsReadOnlyField(label: 'Path', value: entry.path),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton(
              onPressed: onAssign,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      entry.assigned ? 'Assigned' : 'Use for profile',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCreate,
              tooltip: 'Add tool config',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: onDuplicate,
              tooltip: 'Duplicate tool config',
              icon: const Icon(Icons.content_copy),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete tool config',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsToolConfigDropdown extends StatelessWidget {
  const _SettingsToolConfigDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final ValueChanged<ConfigFileEntry> onChanged;

  /// Builds a filename-based selector for tool config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.fileLabel, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsLocalExecCard extends StatelessWidget {
  const _SettingsLocalExecCard({
    required this.config,
    required this.onChanged,
    required this.onAddCommand,
    required this.onDeleteCommand,
    required this.onCommandChanged,
  });

  final LocalExecToolConfig config;
  final ValueChanged<LocalExecToolConfig> onChanged;
  final VoidCallback onAddCommand;
  final ValueChanged<int> onDeleteCommand;
  final void Function(int index, LocalExecCommandConfig command)
  onCommandChanged;

  /// Builds local OS command tool settings.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Local OS tools',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: 'local_exec + request_command',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        SettingsToggleField(
          title: 'Persistent approvals',
          subtitle: 'Allow saved request_command approvals',
          value: config.allowPersistentApprovals,
          onChanged: (value) =>
              onChanged(config.copyWith(allowPersistentApprovals: value)),
        ),
        _SettingsInlineField(
          label: 'Default timeout',
          value: config.defaultTimeout,
          onChanged: (value) =>
              onChanged(config.copyWith(defaultTimeout: value)),
        ),
        _SettingsInlineField(
          label: 'Default max output bytes',
          value: config.defaultMaxOutputBytes == 0
              ? ''
              : config.defaultMaxOutputBytes.toString(),
          onChanged: (value) => onChanged(
            config.copyWith(defaultMaxOutputBytes: int.tryParse(value) ?? 0),
          ),
        ),
        _SettingsLineListField(
          label: 'Allowed workdirs',
          values: config.allowedWorkdirs,
          onChanged: (values) =>
              onChanged(config.copyWith(allowedWorkdirs: values)),
        ),
        const SizedBox(height: 4),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddCommand,
              icon: const Icon(Icons.add),
              label: const Text('Add command'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.commands.isEmpty)
          const PanelEmptyBlock(label: 'No local commands configured')
        else
          for (var index = 0; index < config.commands.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsLocalExecCommandEditor(
              command: config.commands[index],
              onDelete: () => onDeleteCommand(index),
              onChanged: (command) => onCommandChanged(index, command),
            ),
          ],
      ],
    );
  }
}

class _SettingsLocalExecCommandEditor extends StatelessWidget {
  const _SettingsLocalExecCommandEditor({
    required this.command,
    required this.onChanged,
    required this.onDelete,
  });

  final LocalExecCommandConfig command;
  final ValueChanged<LocalExecCommandConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable local command alias.
  @override
  Widget build(BuildContext context) {
    final approval = command.approval;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  command.name.isEmpty ? 'Local command' : command.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete command',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: command.name,
            onChanged: (value) => onChanged(command.copyWith(name: value)),
          ),
          _SettingsInlineField(
            label: 'Executable',
            value: command.executable,
            onChanged: (value) =>
                onChanged(command.copyWith(executable: value)),
          ),
          _SettingsInlineField(
            label: 'Description',
            value: command.description,
            onChanged: (value) =>
                onChanged(command.copyWith(description: value)),
          ),
          _SettingsLineListField(
            label: 'Args',
            values: command.args,
            onChanged: (values) => onChanged(command.copyWith(args: values)),
          ),
          _SettingsInlineField(
            label: 'Timeout',
            value: command.timeout,
            onChanged: (value) => onChanged(command.copyWith(timeout: value)),
          ),
          _SettingsInlineField(
            label: 'Max output bytes',
            value: command.maxOutputBytes == 0
                ? ''
                : command.maxOutputBytes.toString(),
            onChanged: (value) => onChanged(
              command.copyWith(maxOutputBytes: int.tryParse(value) ?? 0),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow',
            subtitle: 'Skip review for this alias',
            value: approval.alwaysAllow,
            onChanged: (value) => onChanged(
              command.copyWith(approval: approval.copyWith(alwaysAllow: value)),
            ),
          ),
          SettingsToggleField(
            title: 'Always allow within workspace',
            subtitle: 'Skip review when cwd stays in workspace',
            value: approval.alwaysAllowWithinWorkspace,
            onChanged: (value) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowWithinWorkspace: value),
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Always allow starts with',
            values: approval.alwaysAllowCommandPrefixes,
            onChanged: (values) => onChanged(
              command.copyWith(
                approval: approval.copyWith(alwaysAllowCommandPrefixes: values),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMcpToolsetsCard extends StatelessWidget {
  const _SettingsMcpToolsetsCard({
    required this.config,
    required this.profileServers,
    required this.onChanged,
    required this.onAddServer,
    required this.onDeleteServer,
    required this.onServerChanged,
  });

  final McpToolConfig config;
  final List<McpServerRuntime> profileServers;
  final ValueChanged<McpToolConfig> onChanged;
  final VoidCallback onAddServer;
  final ValueChanged<int> onDeleteServer;
  final void Function(int index, McpServerToolConfig server) onServerChanged;

  /// Builds MCP server toolset settings.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'MCP toolsets',
      children: <Widget>[
        SettingsToggleField(
          title: 'Enabled',
          subtitle: '${config.servers.length} configured servers',
          value: config.enabled,
          onChanged: (enabled) => onChanged(config.copyWith(enabled: enabled)),
        ),
        if (profileServers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          _SettingsProfileMcpList(servers: profileServers),
        ],
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add),
              label: const Text('Add MCP server'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.servers.isEmpty)
          const PanelEmptyBlock(label: 'No MCP toolsets configured')
        else
          for (var index = 0; index < config.servers.length; index++) ...[
            if (index > 0)
              const SizedBox(height: SettingsFormMetrics.compactGap),
            _SettingsMcpServerEditor(
              server: config.servers[index],
              onDelete: () => onDeleteServer(index),
              onChanged: (server) => onServerChanged(index, server),
            ),
          ],
      ],
    );
  }
}

class _SettingsProfileMcpList extends StatelessWidget {
  const _SettingsProfileMcpList({required this.servers});

  final List<McpServerRuntime> servers;

  /// Builds profile MCP endpoints that can be bridged into harness tools.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final server in servers)
            InputChip(
              avatar: const Icon(Icons.hub_outlined, size: 16),
              label: Text(server.kind.isEmpty ? server.label : server.kind),
              tooltip: server.endpoint,
              onPressed: null,
            ),
        ],
      ),
    );
  }
}

class _SettingsMcpServerEditor extends StatelessWidget {
  const _SettingsMcpServerEditor({
    required this.server,
    required this.onChanged,
    required this.onDelete,
  });

  final McpServerToolConfig server;
  final ValueChanged<McpServerToolConfig> onChanged;
  final VoidCallback onDelete;

  /// Builds one editable MCP server toolset.
  @override
  Widget build(BuildContext context) {
    final transport = normalizedMcpTransport(server.transport);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  server.name.isEmpty ? 'MCP server' : server.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete MCP server',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _SettingsInlineField(
            label: 'Name',
            value: server.name,
            onChanged: (value) => onChanged(server.copyWith(name: value)),
          ),
          _SettingsMcpTransportDropdown(
            value: transport,
            onChanged: (value) => onChanged(
              server.copyWith(
                transport: value,
                command: value == 'stdio' ? server.command : '',
                args: value == 'stdio' ? server.args : const <String>[],
                endpoint: value == 'stdio' ? '' : mcpServerEndpoint(server),
                url: '',
              ),
            ),
          ),
          if (transport == 'stdio') ...<Widget>[
            _SettingsInlineField(
              label: 'Command',
              value: server.command,
              onChanged: (value) => onChanged(server.copyWith(command: value)),
            ),
            _SettingsLineListField(
              label: 'Args',
              values: server.args,
              onChanged: (values) => onChanged(server.copyWith(args: values)),
            ),
            _SettingsKeyValueField(
              label: 'Env',
              values: server.env,
              onChanged: (values) => onChanged(server.copyWith(env: values)),
            ),
          ] else
            _SettingsInlineField(
              label: 'Endpoint',
              value: mcpServerEndpoint(server),
              onChanged: (value) =>
                  onChanged(server.copyWith(endpoint: value, url: '')),
            ),
          _SettingsLineListField(
            label: 'Allowed tools',
            values: server.tools.allow,
            onChanged: (values) => onChanged(
              server.copyWith(tools: server.tools.copyWith(allow: values)),
            ),
          ),
          SettingsToggleField(
            title: 'Require confirmation',
            subtitle: 'All tools on this server',
            value: server.requireConfirmation,
            onChanged: (value) => onChanged(
              server.copyWith(
                requireConfirmation: value,
                requireConfirmationTools: value
                    ? const <String>[]
                    : server.requireConfirmationTools,
              ),
            ),
          ),
          _SettingsLineListField(
            label: 'Require confirmation tools',
            values: server.requireConfirmationTools,
            onChanged: (values) => onChanged(
              server.copyWith(
                requireConfirmation: false,
                requireConfirmationTools: values,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMcpTransportDropdown extends StatelessWidget {
  const _SettingsMcpTransportDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds an MCP transport selector.
  @override
  Widget build(BuildContext context) {
    final selected = _mcpTransportOptions.contains(value)
        ? value
        : 'streamable-http';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'streamable-http',
            child: Text('streamable-http'),
          ),
          DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        decoration: SettingsInputDecoration.field(context, label: 'Transport'),
      ),
    );
  }
}

const List<String> _mcpTransportOptions = <String>['streamable-http', 'stdio'];

class _SettingsLineListField extends StatelessWidget {
  const _SettingsLineListField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  /// Builds a newline-delimited string-list field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.lines(value)),
    );
  }
}

class _SettingsKeyValueField extends StatelessWidget {
  const _SettingsKeyValueField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;

  /// Builds a newline-delimited KEY=value map field.
  @override
  Widget build(BuildContext context) {
    return _SettingsInlineField(
      label: label,
      value: values.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n'),
      minLines: 2,
      maxLines: 5,
      onChanged: (value) => onChanged(SettingsTextCodec.keyValues(value)),
    );
  }
}

class _SettingsToolYamlPreview extends StatelessWidget {
  const _SettingsToolYamlPreview({required this.document});

  final ToolConfigDocument document;

  /// Builds a read-only YAML preview for the structured tool config.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FormSectionCard(
      title: 'Tool config YAML',
      children: <Widget>[
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              document.toYaml(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalExecCommandDialog extends StatefulWidget {
  const _LocalExecCommandDialog();

  /// Creates state for the add-local-command dialog.
  @override
  State<_LocalExecCommandDialog> createState() =>
      _LocalExecCommandDialogState();
}

class _LocalExecCommandDialogState extends State<_LocalExecCommandDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _executable = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _executable.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Builds the required-field local command dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add command'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Name'),
            ),
            TextField(
              controller: _executable,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Executable',
              ),
            ),
            TextField(
              controller: _description,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Description',
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }

  /// Returns the new command when all required fields are present.
  void _save() {
    final name = _name.text.trim();
    final executable = _executable.text.trim();
    final description = _description.text.trim();
    if (name.isEmpty || executable.isEmpty || description.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      newLocalExecCommandConfig(
        name: name,
        executable: executable,
        description: description,
      ),
    );
  }
}

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({required this.seed});

  final McpServerRuntime? seed;

  /// Creates state for the add-MCP-server dialog.
  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final TextEditingController _name = TextEditingController(
    text: _seedName(),
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.seed?.endpoint ?? '',
  );
  final TextEditingController _command = TextEditingController();
  String _transport = 'streamable-http';

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _command.dispose();
    super.dispose();
  }

  /// Builds the required-field MCP server dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add MCP server'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Name'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _transport,
              decoration: SettingsInputDecoration.field(
                context,
                label: 'Transport',
              ),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(
                  value: 'streamable-http',
                  child: Text('streamable-http'),
                ),
                DropdownMenuItem<String>(value: 'stdio', child: Text('stdio')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _transport = value);
                }
              },
            ),
            if (_transport == 'stdio')
              TextField(
                controller: _command,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Command',
                ),
                onSubmitted: (_) => _save(),
              )
            else
              TextField(
                controller: _endpoint,
                decoration: SettingsInputDecoration.field(
                  context,
                  label: 'Endpoint',
                ),
                onSubmitted: (_) => _save(),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add')),
      ],
    );
  }

  /// Returns a seed name from the runtime profile server.
  String _seedName() {
    final seed = widget.seed;
    if (seed == null) {
      return '';
    }
    return SettingsNameFactory.toolNameFromLabel(
      seed.kind.isEmpty ? seed.id : seed.kind,
    );
  }

  /// Returns the new MCP server when required fields are present.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (_transport == 'stdio') {
      final command = _command.text.trim();
      if (command.isEmpty) {
        return;
      }
      Navigator.of(
        context,
      ).pop(newStdioMcpServerToolConfig(name: name, command: command));
      return;
    }
    final endpoint = _endpoint.text.trim();
    if (endpoint.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(newHttpMcpServerToolConfig(name: name, endpoint: endpoint));
  }
}

class _SettingsConfigFileCollection extends StatefulWidget {
  const _SettingsConfigFileCollection({
    required this.controller,
    required this.title,
    required this.emptyLabel,
    required this.icon,
    required this.kind,
    required this.entries,
    required this.assignedPath,
  });

  final AgentAwesomeAppController controller;
  final String title;
  final String emptyLabel;
  final IconData icon;
  final ConfigFileKind kind;
  final List<ConfigFileEntry> entries;
  final String assignedPath;

  @override
  State<_SettingsConfigFileCollection> createState() =>
      _SettingsConfigFileCollectionState();
}

class _SettingsConfigFileCollectionState
    extends State<_SettingsConfigFileCollection> {
  String? _selectedPath;

  /// Initializes selected config file state.
  @override
  void initState() {
    super.initState();
    _selectedPath = _initialSelectedPath();
  }

  /// Keeps selected config file state valid after collection updates.
  @override
  void didUpdateWidget(covariant _SettingsConfigFileCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedPath == null ||
        !widget.entries.any((entry) => entry.path == _selectedPath)) {
      _selectedPath = _initialSelectedPath();
    }
  }

  /// Builds a collection switcher for agent or tool config files.
  @override
  Widget build(BuildContext context) {
    return CollectionSwitcherPanel<ConfigFileEntry>(
      title: widget.title,
      selectedId: _selectedPath,
      emptyLabel: widget.emptyLabel,
      items: <CollectionPanelItem<ConfigFileEntry>>[
        for (final entry in widget.entries)
          CollectionPanelItem<ConfigFileEntry>(
            id: entry.id,
            label: entry.label,
            detail: entry.path,
            icon: widget.icon,
            badge: entry.assigned ? 'Active' : '',
            value: entry,
          ),
      ],
      onSelect: (id) => setState(() => _selectedPath = id),
      onCreate: () => unawaited(_create()),
      onDuplicate: (entry) => unawaited(_duplicate(entry)),
      onDelete: (entry) => unawaited(_delete(entry)),
      builder: (entry, query) {
        return _SettingsConfigFileEditor(
          controller: widget.controller,
          entry: entry,
          title: '${SettingsConfigLabels.kindLabel(entry.kind)} config file',
          query: query,
          onRenamed: (path) => setState(() => _selectedPath = path),
        );
      },
    );
  }

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

  Future<void> _create() async {
    try {
      final path = await widget.controller.createConfigFile(widget.kind);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedPath = path;
      });
    } catch (_) {}
  }

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

class _SettingsConfigFileEditor extends StatefulWidget {
  const _SettingsConfigFileEditor({
    required this.controller,
    required this.entry,
    required this.title,
    required this.query,
    required this.onRenamed,
  });

  final AgentAwesomeAppController controller;
  final ConfigFileEntry entry;
  final String title;
  final String query;
  final ValueChanged<String> onRenamed;

  @override
  State<_SettingsConfigFileEditor> createState() =>
      _SettingsConfigFileEditorState();
}

class _SettingsConfigFileEditorState extends State<_SettingsConfigFileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.entry.label,
  );
  late String _savedName = widget.entry.label;

  /// Cleans up config editor controllers.
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Keeps the editable name synchronized with the selected file.
  @override
  void didUpdateWidget(covariant _SettingsConfigFileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.path != widget.entry.path) {
      _name.text = widget.entry.label;
      _savedName = widget.entry.label;
    }
  }

  /// Builds the selected model or agent config editor.
  @override
  Widget build(BuildContext context) {
    if (!SettingsQuery.matches(widget.query, <String>[
      widget.entry.label,
      widget.entry.path,
    ])) {
      return PanelEmptyState(query: widget.query);
    }
    return FormPanel(
      children: <Widget>[
        FormSectionCard(
          title: 'Details',
          children: <Widget>[
            _SettingsAutoSaveTextField(
              label: 'Name',
              controller: _name,
              initialSavedValue: _savedName,
              onSave: _rename,
            ),
            _SettingsReadOnlyField(label: 'Path', value: widget.entry.path),
            _SettingsActionRow(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: widget.entry.assigned
                      ? null
                      : () => unawaited(_assign()),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    widget.entry.assigned ? 'Assigned' : 'Use for profile',
                  ),
                ),
              ],
            ),
          ],
        ),
        _SettingsTextFileEditor(
          controller: widget.controller,
          title: widget.title,
          path: widget.entry.path,
        ),
      ],
    );
  }

  Future<void> _assign() async {
    try {
      await widget.controller.assignConfigFile(widget.entry);
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  Future<void> _rename(String value) async {
    try {
      final path = await widget.controller.renameConfigFile(
        widget.entry,
        value,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _savedName = value.trim();
      });
      widget.onRenamed(path);
    } catch (_) {}
  }
}

class _SettingsServerContent extends StatefulWidget {
  const _SettingsServerContent({
    required this.profile,
    required this.controller,
    required this.title,
    required this.servers,
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;
  final String title;
  final List<McpServerRuntime> servers;

  /// Creates state for MCP server settings selection.
  @override
  State<_SettingsServerContent> createState() => _SettingsServerContentState();
}

class _SettingsServerContentState extends State<_SettingsServerContent> {
  String? _selectedServerId;

  /// Initializes the selected server.
  @override
  void initState() {
    super.initState();
    _selectedServerId = _initialSelectedServerId();
  }

  /// Keeps the selected server valid when profile bindings change.
  @override
  void didUpdateWidget(covariant _SettingsServerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedServerId == null ||
        !widget.servers.any((server) => server.id == _selectedServerId)) {
      _selectedServerId = _initialSelectedServerId();
    }
  }

  /// Builds MCP server binding details for one server kind.
  @override
  Widget build(BuildContext context) {
    return CollectionSwitcherPanel<McpServerRuntime>(
      title: widget.title,
      selectedId: _selectedServerId,
      emptyLabel: 'No servers configured',
      items: <CollectionPanelItem<McpServerRuntime>>[
        for (final server in widget.servers)
          CollectionPanelItem<McpServerRuntime>(
            id: server.id,
            label: server.label.isEmpty ? server.id : server.label,
            detail: server.endpoint,
            icon: Icons.hub_outlined,
            badge: server.enabled ? 'Active' : '',
            value: server,
          ),
      ],
      onSelect: (id) => setState(() => _selectedServerId = id),
      builder: (server, query) {
        if (!SettingsQuery.matches(query, <String>[
          server.id,
          server.label,
          server.kind,
          server.endpoint,
          server.healthUrl,
          server.workingDirectory,
          server.packagePath,
          server.arguments.join(' '),
        ])) {
          return PanelEmptyState(query: query);
        }
        return FormPanel(
          children: <Widget>[
            _SettingsServerTile(
              profile: widget.profile,
              controller: widget.controller,
              server: server,
            ),
          ],
        );
      },
    );
  }

  /// Returns the initially selected MCP server id.
  String? _initialSelectedServerId() {
    if (widget.servers.isEmpty) {
      return null;
    }
    return widget.servers.first.id;
  }
}

class _SettingsModelProviderCard extends StatelessWidget {
  const _SettingsModelProviderCard({
    required this.controller,
    required this.provider,
    required this.onChanged,
  });

  final AgentAwesomeAppController controller;
  final ModelProviderConfig provider;
  final ValueChanged<ModelProviderConfig> onChanged;

  /// Builds one editable provider card and its model rows.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: provider.displayName,
      children: <Widget>[
        SettingsFieldGrid(
          children: <Widget>[
            _SettingsInlineField(
              label: 'Name',
              value: provider.name,
              onChanged: (value) => onChanged(provider.copyWith(name: value)),
            ),
            _SettingsAdapterDropdown(
              value: provider.adapter,
              onChanged: (value) =>
                  onChanged(provider.copyWith(adapter: value)),
            ),
          ],
        ),
        _SettingsCredentialField(
          controller: controller,
          providerId: provider.id,
          reference: provider.apiKey,
          onChanged: (value) => onChanged(provider.copyWith(apiKey: value)),
        ),
        _SettingsInlineField(
          label: 'URL',
          value: provider.url,
          onChanged: (value) => onChanged(provider.copyWith(url: value)),
        ),
        const SizedBox(height: SettingsFormMetrics.sectionGap),
        SettingsFormSubsection(
          title: 'Models',
          children: <Widget>[
            for (var index = 0; index < provider.models.length; index++)
              _SettingsModelRow(
                model: provider.models[index],
                onChanged: (model) => _replaceModel(index, model),
                onDelete: provider.models.length <= 1
                    ? null
                    : () => _deleteModel(index),
              ),
            _SettingsProviderDefaultModelDropdown(
              provider: provider,
              onChanged: (value) =>
                  onChanged(provider.copyWith(defaultModel: value)),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add),
                  label: const Text('Add model'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _addModel() {
    final nextId = SettingsConfigIds.uniqueModelId(provider, 'model');
    onChanged(
      provider.copyWith(
        models: <ModelConfigModel>[
          ...provider.models,
          ModelConfigModel(id: nextId, model: 'provider-model-name'),
        ],
      ),
    );
  }

  void _replaceModel(int index, ModelConfigModel model) {
    final previous = provider.models[index];
    final nextDefault = provider.defaultModel == previous.id
        ? model.id
        : provider.defaultModel;
    onChanged(
      provider.copyWith(
        defaultModel: nextDefault,
        models: <ModelConfigModel>[
          for (var i = 0; i < provider.models.length; i++)
            i == index ? model : provider.models[i],
        ],
      ),
    );
  }

  void _deleteModel(int index) {
    final nextModels = <ModelConfigModel>[
      for (var i = 0; i < provider.models.length; i++)
        if (i != index) provider.models[i],
    ];
    final nextDefault = provider.defaultModel == provider.models[index].id
        ? nextModels.first.id
        : provider.defaultModel;
    onChanged(provider.copyWith(models: nextModels, defaultModel: nextDefault));
  }
}

class _SettingsModelProviderYamlPreview extends StatelessWidget {
  const _SettingsModelProviderYamlPreview({required this.provider});

  final ModelProviderConfig provider;

  /// Builds a selected-provider YAML preview without exposing sibling providers.
  @override
  Widget build(BuildContext context) {
    final colors = context.agentAwesomeColors;
    return FormSectionCard(
      title: 'Provider YAML',
      children: <Widget>[
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              modelProviderConfigYaml(provider),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsAdapterDropdown extends StatelessWidget {
  const _SettingsAdapterDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Builds a constrained selector for supported harness adapters.
  @override
  Widget build(BuildContext context) {
    final selected = supportedModelAdapters.contains(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final adapter in supportedModelAdapters)
            DropdownMenuItem<String>(value: adapter, child: Text(adapter)),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        decoration: SettingsInputDecoration.field(context, label: 'Adapter'),
      ),
    );
  }
}

class _SettingsCredentialField extends StatefulWidget {
  const _SettingsCredentialField({
    required this.controller,
    required this.providerId,
    required this.reference,
    required this.onChanged,
  });

  final AgentAwesomeAppController controller;
  final String providerId;
  final String reference;
  final ValueChanged<String> onChanged;

  /// Creates state for an async masked credential lookup field.
  @override
  State<_SettingsCredentialField> createState() =>
      _SettingsCredentialFieldState();
}

class _SettingsCredentialFieldState extends State<_SettingsCredentialField> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  CredentialLookup? _lookup;
  bool _loading = true;
  bool _saving = false;

  /// Loads the initial credential display state.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Cleans up secret input state.
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reloads when the configured credential reference changes.
  @override
  void didUpdateWidget(covariant _SettingsCredentialField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _lookup = null;
      _loading = true;
      unawaited(_load());
    }
  }

  /// Builds a password-style API key field backed by the OS keyring.
  @override
  Widget build(BuildContext context) {
    final lookup = _lookup;
    final hasTypedSecret = _controller.text.isNotEmpty;
    final canReveal = hasTypedSecret || (lookup?.found ?? false);
    final copyableSecret = _copyableSecret(lookup, hasTypedSecret);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controller,
        obscureText: hasTypedSecret && _obscureText,
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => unawaited(_saveSecret()),
        decoration: SettingsInputDecoration.field(
          context,
          label: 'API key',
          floatingLabelBehavior: lookup?.found ?? false
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          hintText: _hintText(lookup),
          suffixIcon: Wrap(
            spacing: 2,
            children: <Widget>[
              IconButton(
                onPressed: canReveal
                    ? () => setState(() => _obscureText = !_obscureText)
                    : null,
                tooltip: _obscureText ? 'Show API key' : 'Hide API key',
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              if (copyableSecret.isNotEmpty)
                IconButton(
                  onPressed: () => unawaited(_copySecret(copyableSecret)),
                  tooltip: 'Copy API key',
                  icon: const Icon(Icons.copy_outlined),
                ),
              IconButton(
                onPressed: hasTypedSecret && !_saving
                    ? () => unawaited(_saveSecret())
                    : null,
                tooltip: 'Save API key to OS keyring',
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
              ),
              IconButton(
                onPressed: widget.reference.trim().isNotEmpty && !_saving
                    ? () => unawaited(_deleteSecret())
                    : null,
                tooltip: 'Delete API key from OS keyring',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          suffixIconConstraints: BoxConstraints(
            minWidth: copyableSecret.isEmpty ? 144 : 192,
          ),
        ),
      ),
    );
  }

  /// Copies the revealed API key.
  Future<void> _copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
  }

  /// Saves the typed API key into the OS keyring.
  Future<void> _saveSecret() async {
    final secret = _controller.text.trim();
    if (secret.isEmpty) {
      return;
    }
    final reference = _credentialReference();
    setState(() {
      _saving = true;
    });
    final result = await widget.controller.storeCredential(
      reference: reference,
      secret: secret,
    );
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _saving = false;
      });
      return;
    }
    _controller.clear();
    widget.onChanged(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
      _obscureText = true;
    });
  }

  /// Deletes the configured API key from the OS keyring.
  Future<void> _deleteSecret() async {
    final reference = widget.reference.trim();
    if (reference.isEmpty) {
      return;
    }
    final confirmed = await _confirmSettingsDelete(
      context,
      label: 'API key credential',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await widget.controller.deleteCredential(reference);
    final lookup = await widget.controller.lookupCredential(reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
      _saving = false;
    });
  }

  /// Returns the existing credential reference or generates a provider default.
  String _credentialReference() {
    final current = widget.reference.trim();
    if (current.isNotEmpty) {
      return current;
    }
    return SettingsNameFactory.credentialNameFromProvider(widget.providerId);
  }

  /// Returns the field display text for missing, masked, or revealed secrets.
  String _hintText(CredentialLookup? lookup) {
    if (_loading) {
      return '';
    }
    if (lookup != null && lookup.found) {
      final value = _obscureText ? lookup.displayValue : lookup.secretValue;
      return '${lookup.source}: $value';
    }
    return 'Paste API key';
  }

  /// Returns the current secret when an API key is present.
  String _copyableSecret(CredentialLookup? lookup, bool hasTypedSecret) {
    if (hasTypedSecret) {
      return _controller.text;
    }
    if (lookup != null && lookup.found) {
      return lookup.secretValue;
    }
    return '';
  }

  Future<void> _load() async {
    final lookup = await widget.controller.lookupCredential(widget.reference);
    if (!mounted) {
      return;
    }
    setState(() {
      _lookup = lookup;
      _loading = false;
    });
  }
}

class _SettingsProviderDefaultModelDropdown extends StatelessWidget {
  const _SettingsProviderDefaultModelDropdown({
    required this.provider,
    required this.onChanged,
  });

  final ModelProviderConfig provider;
  final ValueChanged<String> onChanged;

  /// Builds a provider-local default model selector.
  @override
  Widget build(BuildContext context) {
    final modelIds = provider.models.map((model) => model.id).toList();
    final selected = modelIds.contains(provider.defaultModel)
        ? provider.defaultModel
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final modelId in modelIds)
            DropdownMenuItem<String>(value: modelId, child: Text(modelId)),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
        decoration: SettingsInputDecoration.field(
          context,
          label: 'Default model',
        ),
      ),
    );
  }
}

class _SettingsModelRow extends StatelessWidget {
  const _SettingsModelRow({
    required this.model,
    required this.onChanged,
    required this.onDelete,
  });

  final ModelConfigModel model;
  final ValueChanged<ModelConfigModel> onChanged;
  final VoidCallback? onDelete;

  /// Builds one editable model row.
  @override
  Widget build(BuildContext context) {
    return SettingsFieldRow(
      trailing: IconButton(
        onPressed: onDelete,
        tooltip: 'Delete model',
        icon: const Icon(Icons.delete_outline),
      ),
      child: SettingsFieldGrid(
        children: <Widget>[
          _SettingsInlineField(
            label: 'Model id',
            value: model.id,
            onChanged: (value) => onChanged(model.copyWith(id: value)),
          ),
          _SettingsInlineField(
            label: 'Provider model',
            value: model.model,
            onChanged: (value) => onChanged(model.copyWith(model: value)),
          ),
        ],
      ),
    );
  }
}

class _SettingsInlineField extends StatefulWidget {
  const _SettingsInlineField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  /// Creates state for blur-based inline settings edits.
  @override
  State<_SettingsInlineField> createState() => _SettingsInlineFieldState();
}

class _SettingsInlineFieldState extends State<_SettingsInlineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.value;

  /// Initializes focus tracking for blur saves.
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  /// Keeps field text synchronized when the backing model changes.
  @override
  void didUpdateWidget(covariant _SettingsInlineField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value;
      _savedValue = widget.value;
    }
  }

  /// Cleans up field controllers.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Builds a compact settings text field that saves on change.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        focusNode: _focusNode,
        controller: _controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        onFieldSubmitted: (_) => _save(),
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Saves changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _save();
    }
  }

  /// Emits the new value when it differs from the saved value.
  void _save() {
    final next = _controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    widget.onChanged(next);
  }
}

class _SettingsReadOnlyField extends StatelessWidget {
  const _SettingsReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  /// Builds a read-only settings field.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsAutoSaveTextField extends StatefulWidget {
  const _SettingsAutoSaveTextField({
    required this.label,
    required this.controller,
    required this.initialSavedValue,
    required this.onSave,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String initialSavedValue;
  final Future<void> Function(String value) onSave;
  final int minLines;
  final int maxLines;

  @override
  State<_SettingsAutoSaveTextField> createState() =>
      _SettingsAutoSaveTextFieldState();
}

class _SettingsAutoSaveTextFieldState
    extends State<_SettingsAutoSaveTextField> {
  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.initialSavedValue;

  /// Initializes focus tracking for blur autosave.
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  /// Synchronizes saved value when the selected backing item changes.
  @override
  void didUpdateWidget(covariant _SettingsAutoSaveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSavedValue != widget.initialSavedValue) {
      _savedValue = widget.initialSavedValue;
    }
  }

  /// Cleans up field focus state.
  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// Builds an editable field that saves when focus leaves it.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        focusNode: _focusNode,
        controller: widget.controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Saves changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      return;
    }
    final next = widget.controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    unawaited(widget.onSave(next));
  }
}

class _SettingsConfigDropdown extends StatelessWidget {
  const _SettingsConfigDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final ValueChanged<ConfigFileEntry> onChanged;

  /// Builds a profile assignment dropdown for config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsMcpServerAssignmentDropdown extends StatelessWidget {
  const _SettingsMcpServerAssignmentDropdown({
    required this.label,
    required this.kind,
    required this.servers,
    required this.onChanged,
  });

  final String label;
  final String kind;
  final List<McpServerRuntime> servers;
  final ValueChanged<McpServerRuntime> onChanged;

  /// Builds a role-specific MCP server assignment dropdown.
  @override
  Widget build(BuildContext context) {
    final choices = servers.where((server) => server.kind == kind).toList();
    final selected = _selectedServerId(choices);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final server in choices)
            DropdownMenuItem<String>(
              value: server.id,
              child: Text(_labelFor(server), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: choices.isEmpty
            ? null
            : (id) {
                if (id == null) {
                  return;
                }
                for (final server in choices) {
                  if (server.id == id) {
                    onChanged(server);
                    return;
                  }
                }
              },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }

  /// Returns the active server id for this MCP role.
  String? _selectedServerId(List<McpServerRuntime> choices) {
    for (final server in choices) {
      if (server.enabled) {
        return server.id;
      }
    }
    return choices.isEmpty ? null : choices.first.id;
  }

  /// Returns a readable server label for assignment choices.
  String _labelFor(McpServerRuntime server) {
    if (server.label.trim().isNotEmpty) {
      return server.label;
    }
    return server.id;
  }
}

/// _SummaryModelOption describes one exact model available for app summaries.
class _SummaryModelOption {
  /// Creates an app summary model dropdown option.
  const _SummaryModelOption({
    required this.configPath,
    required this.modelRef,
    required this.label,
    required this.isConfigDefault,
  });

  /// Model config file containing this option.
  final String configPath;

  /// Provider:model reference inside the model config file.
  final String modelRef;

  /// Human-readable dropdown label.
  final String label;

  /// Whether this option matches the config file's top-level default.
  final bool isConfigDefault;
}

/// _SettingsSummaryModelDropdown selects a provider:model for title summaries.
class _SettingsSummaryModelDropdown extends StatelessWidget {
  /// Creates an exact summary model selector.
  const _SettingsSummaryModelDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.selectedModelRef,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final String selectedModelRef;
  final ValueChanged<_SummaryModelOption> onChanged;

  /// Builds a dropdown of exact app-owned model choices.
  @override
  Widget build(BuildContext context) {
    final options = _options();
    final selected = _selectedOption(options);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<_SummaryModelOption>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<_SummaryModelOption>>[
          for (final option in options)
            DropdownMenuItem<_SummaryModelOption>(
              value: option,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: options.isEmpty
            ? null
            : (option) {
                if (option != null) {
                  onChanged(option);
                }
              },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }

  /// Returns flattened provider:model choices from config file metadata.
  List<_SummaryModelOption> _options() {
    final options = <_SummaryModelOption>[];
    final multipleConfigs = entries.length > 1;
    for (final entry in entries) {
      for (final choice in entry.modelChoices) {
        options.add(
          _SummaryModelOption(
            configPath: entry.path,
            modelRef: choice.ref,
            label: SettingsConfigLabels.summaryModelLabel(
              entry: entry,
              choice: choice,
              includeConfig: multipleConfigs,
            ),
            isConfigDefault: choice.isDefault,
          ),
        );
      }
    }
    return options;
  }

  /// Returns the currently selected option, falling back to config defaults.
  _SummaryModelOption? _selectedOption(List<_SummaryModelOption> options) {
    if (options.isEmpty) {
      return null;
    }
    final selectedPath = this.selectedPath.trim();
    final selectedRef = selectedModelRef.trim();
    if (selectedPath.isNotEmpty && selectedRef.isNotEmpty) {
      for (final option in options) {
        if (option.configPath == selectedPath &&
            option.modelRef == selectedRef) {
          return option;
        }
      }
    }
    if (selectedPath.isNotEmpty) {
      for (final option in options) {
        if (option.configPath == selectedPath && option.isConfigDefault) {
          return option;
        }
      }
      for (final option in options) {
        if (option.configPath == selectedPath) {
          return option;
        }
      }
    }
    return options.first;
  }
}

/// _SettingsProfileDropdown selects one configured runtime profile file.
class _SettingsProfileDropdown extends StatelessWidget {
  /// Creates a runtime profile dropdown for app settings.
  const _SettingsProfileDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  /// Field label shown above the dropdown.
  final String label;

  /// Runtime profiles available for selection.
  final List<RuntimeProfileFileEntry> entries;

  /// Currently selected profile path.
  final String selectedPath;

  /// Callback fired with the selected profile entry.
  final ValueChanged<RuntimeProfileFileEntry> onChanged;

  /// Builds an app setting dropdown for runtime profile files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({required this.children});

  final List<Widget> children;

  /// Builds settings action buttons with standard spacing.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: children),
    );
  }
}

/// Confirms a destructive settings deletion.
Future<bool> _confirmSettingsDelete(
  BuildContext context, {
  required String label,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete configuration'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

class _SettingsTextFileEditor extends StatefulWidget {
  const _SettingsTextFileEditor({
    required this.controller,
    required this.title,
    required this.path,
  });

  final AgentAwesomeAppController controller;
  final String title;
  final String path;

  @override
  State<_SettingsTextFileEditor> createState() =>
      _SettingsTextFileEditorState();
}

class _SettingsTextFileEditorState extends State<_SettingsTextFileEditor> {
  final TextEditingController _content = TextEditingController();
  final FocusNode _contentFocus = FocusNode();
  String _savedContent = '';
  bool _loading = true;

  /// Loads the file editor content.
  @override
  void initState() {
    super.initState();
    _contentFocus.addListener(_handleContentFocusChange);
    unawaited(_load());
  }

  /// Reloads editor content when the target file path changes.
  @override
  void didUpdateWidget(covariant _SettingsTextFileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      unawaited(_load());
    }
  }

  /// Cleans up the text editor controller.
  @override
  void dispose() {
    _contentFocus.removeListener(_handleContentFocusChange);
    _contentFocus.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Builds a raw editor for the referenced configuration file.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: widget.title,
      children: <Widget>[
        _SettingsReadOnlyField(label: 'Path', value: widget.path),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          TextFormField(
            focusNode: _contentFocus,
            controller: _content,
            minLines: 14,
            maxLines: 28,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: SettingsInputDecoration.field(
              context,
              alignLabelWithHint: true,
              label: 'File content',
            ),
          ),
        const SizedBox(height: 12),
        _SettingsActionRow(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      _content.text = await widget.controller.readConfigurationFile(
        widget.path,
      );
      _savedContent = _content.text;
      if (!mounted) {
        return;
      }
    } catch (error) {
      _content.text = '';
      _savedContent = '';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_content.text == _savedContent) {
      return;
    }
    try {
      await widget.controller.saveConfigurationFile(widget.path, _content.text);
      _savedContent = _content.text;
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }

  /// Saves changed file content after focus leaves the editor.
  void _handleContentFocusChange() {
    if (_contentFocus.hasFocus || _loading) {
      return;
    }
    unawaited(_save());
  }
}

class _SettingsServerTile extends StatefulWidget {
  const _SettingsServerTile({
    required this.profile,
    required this.controller,
    required this.server,
  });

  final RuntimeProfile profile;
  final AgentAwesomeAppController controller;
  final McpServerRuntime server;

  @override
  State<_SettingsServerTile> createState() => _SettingsServerTileState();
}

class _SettingsServerTileState extends State<_SettingsServerTile> {
  late final TextEditingController _id = TextEditingController(
    text: widget.server.id,
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.server.label,
  );
  late final TextEditingController _endpoint = TextEditingController(
    text: widget.server.endpoint,
  );
  late final TextEditingController _healthUrl = TextEditingController(
    text: widget.server.healthUrl,
  );
  late final TextEditingController _workingDirectory = TextEditingController(
    text: widget.server.workingDirectory,
  );
  late final TextEditingController _packagePath = TextEditingController(
    text: widget.server.packagePath,
  );
  late final TextEditingController _arguments = TextEditingController(
    text: widget.server.arguments.join('\n'),
  );
  late bool _enabled = widget.server.enabled;
  late bool _autoStart = widget.server.autoStart;

  /// Cleans up MCP server form controllers.
  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _endpoint.dispose();
    _healthUrl.dispose();
    _workingDirectory.dispose();
    _packagePath.dispose();
    _arguments.dispose();
    super.dispose();
  }

  /// Builds one MCP binding tile from the active profile.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: widget.server.label.isEmpty ? 'MCP binding' : widget.server.label,
      children: <Widget>[
        SettingsFieldRow(
          leading: Switch(
            value: _enabled,
            onChanged: (value) {
              setState(() => _enabled = value);
              unawaited(_save());
            },
          ),
          trailing: PanelBadge(label: _autoStart ? 'Managed' : 'External'),
          child: _SettingsAutoSaveTextField(
            label: 'Label',
            controller: _label,
            initialSavedValue: widget.server.label,
            onSave: (_) => _save(),
          ),
        ),
        _SettingsAutoSaveTextField(
          label: 'Server ID',
          controller: _id,
          initialSavedValue: widget.server.id,
          onSave: (_) => _save(),
        ),
        _SettingsAutoSaveTextField(
          label: 'Endpoint',
          controller: _endpoint,
          initialSavedValue: widget.server.endpoint,
          onSave: (_) => _save(),
        ),
        _SettingsAutoSaveTextField(
          label: 'Health URL',
          controller: _healthUrl,
          initialSavedValue: widget.server.healthUrl,
          onSave: (_) => _save(),
        ),
        _SettingsAutoSaveTextField(
          label: 'Working directory',
          controller: _workingDirectory,
          initialSavedValue: widget.server.workingDirectory,
          onSave: (_) => _save(),
        ),
        _SettingsAutoSaveTextField(
          label: 'Package path',
          controller: _packagePath,
          initialSavedValue: widget.server.packagePath,
          onSave: (_) => _save(),
        ),
        _SettingsAutoSaveTextField(
          label: 'Arguments, one per line',
          controller: _arguments,
          initialSavedValue: widget.server.arguments.join('\n'),
          onSave: (_) => _save(),
          minLines: 3,
          maxLines: 8,
        ),
        SettingsToggleField(
          title: 'Auto-start server',
          value: _autoStart,
          onChanged: (value) {
            setState(() => _autoStart = value);
            unawaited(_save());
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    final replacement = widget.server.copyWith(
      id: _id.text.trim(),
      label: _label.text.trim(),
      endpoint: _endpoint.text.trim(),
      healthUrl: _healthUrl.text.trim(),
      workingDirectory: _workingDirectory.text.trim(),
      packagePath: _packagePath.text.trim(),
      arguments: _arguments.text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(),
      autoStart: _autoStart,
      enabled: _enabled,
    );
    try {
      await widget.controller.saveRequiredServerRuntime(
        originalId: widget.server.id,
        server: replacement,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (_) {}
  }
}
