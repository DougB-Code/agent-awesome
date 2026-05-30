/// App-wide settings content widgets.
part of 'settings_panel.dart';

class _SettingsAppContent extends StatefulWidget {
  const _SettingsAppContent({required this.controller, required this.query});

  final AgentAwesomeAppController controller;
  final String query;

  /// Creates state for app-specific settings edits.
  @override
  State<_SettingsAppContent> createState() => _SettingsAppContentState();
}

class _SettingsAppContentState extends State<_SettingsAppContent> {
  final SettingsSaveFeedbackController _agentFeedback =
      SettingsSaveFeedbackController();
  final SettingsSaveFeedbackController _memoryFeedback =
      SettingsSaveFeedbackController();
  final SettingsSaveFeedbackController _summaryToggleFeedback =
      SettingsSaveFeedbackController();
  final SettingsSaveFeedbackController _summaryModelFeedback =
      SettingsSaveFeedbackController();

  /// Cleans up save feedback controllers.
  @override
  void dispose() {
    _agentFeedback.dispose();
    _memoryFeedback.dispose();
    _summaryToggleFeedback.dispose();
    _summaryModelFeedback.dispose();
    super.dispose();
  }

  /// Builds app-owned settings that are intentionally outside topology files.
  @override
  Widget build(BuildContext context) {
    return _buildAppSettings(
      widget.query,
      widget.controller.availableAgentConfigs,
    );
  }

  /// Builds the combined app settings surface.
  Widget _buildAppSettings(String query, List<ConfigFileEntry> agents) {
    if (!SettingsQuery.matches(query, <String>[
      'Chat Defaults',
      'Default agent',
      widget.controller.defaultAgentConfigPath,
      'Default memory',
      widget.controller.selectedMemoryDomainId,
      for (final domain
          in widget.controller.runtimeProfile?.memoryDomains ??
              const <McpServerRuntime>[]) ...<String>[
        domain.id,
        domain.label,
        domain.kind,
      ],
      'Application Models',
      'Generate chat titles',
      'Summary model',
      widget.controller.summaryModelConfigPath,
      widget.controller.summaryModelRef,
      for (final agent in agents) ...<String>[
        agent.label,
        agent.fileLabel,
        agent.path,
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
        FormPlainSection(
          title: 'Chat defaults',
          children: <Widget>[
            SettingsSaveFeedback(
              controller: _agentFeedback,
              child: _SettingsConfigDropdown(
                label: 'Default agent',
                entries: agents,
                selectedPath: widget.controller.defaultAgentConfigPath,
                onChanged: _setDefaultAgent,
              ),
            ),
            SettingsSaveFeedback(
              controller: _memoryFeedback,
              child: _SettingsMemoryDomainDropdown(
                label: 'Default memory',
                domains:
                    widget.controller.runtimeProfile?.memoryDomains ??
                    const <McpServerRuntime>[],
                selectedId: widget.controller.selectedMemoryDomainId,
                onChanged: _setDefaultMemory,
              ),
            ),
          ],
        ),
        FormPlainSection(
          title: 'Application models',
          children: <Widget>[
            SettingsToggleField(
              title: 'Generate chat titles',
              subtitle: 'Summarize titles with a model.',
              value: widget.controller.appSettings.chatTitleSummariesEnabled,
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
    );
  }

  /// Persists the default agent selected for new chats.
  Future<void> _setDefaultAgent(ConfigFileEntry entry) async {
    await _agentFeedback.run(() {
      return widget.controller.selectActiveAgentConfig(entry.path);
    });
  }

  /// Persists the default memory domain selected for new chats.
  Future<void> _setDefaultMemory(McpServerRuntime domain) async {
    await _memoryFeedback.run(() {
      return widget.controller.selectDefaultMemoryDomain(domain.id);
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
