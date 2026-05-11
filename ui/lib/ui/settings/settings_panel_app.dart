/// App-wide settings content widgets.
part of 'settings_panel.dart';

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
