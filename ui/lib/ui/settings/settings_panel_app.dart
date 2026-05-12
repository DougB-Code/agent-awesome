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
  final SettingsSaveFeedbackController _memoryFirewallFeedback =
      SettingsSaveFeedbackController();

  /// Cleans up save feedback controllers.
  @override
  void dispose() {
    _profileFeedback.dispose();
    _summaryToggleFeedback.dispose();
    _summaryModelFeedback.dispose();
    _memoryFirewallFeedback.dispose();
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
      'Memory Firewalls',
      for (final firewall in widget.controller.memoryFirewalls) ...<String>[
        firewall.id,
        firewall.label,
        ...firewall.sharedWith,
        ...firewall.writableBy,
        for (final share in firewall.shares) ...<String>[share.kind, share.id],
        for (final writer in firewall.writers) ...<String>[
          writer.kind,
          writer.id,
        ],
      ],
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
            const SizedBox(height: SettingsFormMetrics.sectionGap),
            SettingsFormSubsection(
              title: 'Memory firewalls',
              children: <Widget>[
                SettingsSaveFeedback(
                  controller: _memoryFirewallFeedback,
                  child: _SettingsInlineField(
                    label:
                        'Firewalls (id=Label | read: kind:id=Name | write: kind:id=Name)',
                    value: _encodeMemoryFirewalls(
                      widget.controller.memoryFirewalls,
                    ),
                    minLines: 6,
                    maxLines: 8,
                    onChanged: _setMemoryFirewalls,
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

  /// Persists memory firewall choices from the settings textarea.
  void _setMemoryFirewalls(String value) {
    unawaited(
      _memoryFirewallFeedback.run(() {
        return widget.controller.setMemoryFirewalls(
          _decodeMemoryFirewalls(value),
        );
      }),
    );
  }
}

/// Encodes memory firewall settings as editable id=Label | shared lines.
String _encodeMemoryFirewalls(List<MemoryFirewall> firewalls) {
  return firewalls
      .map((firewall) {
        final readers = firewall.shares
            .map(_encodeMemoryFirewallShare)
            .join(', ');
        final writers = firewall.writers
            .map(_encodeMemoryFirewallShare)
            .join(', ');
        final grants = <String>[
          if (readers.isNotEmpty) 'read: $readers',
          if (writers.isNotEmpty) 'write: $writers',
        ];
        if (grants.isEmpty) {
          return '${firewall.id}=${firewall.label}';
        }
        return '${firewall.id}=${firewall.label} | ${grants.join(' | ')}';
      })
      .join('\n');
}

/// Decodes memory firewall settings from editable id=Label | shared lines.
List<MemoryFirewall> _decodeMemoryFirewalls(String value) {
  final firewalls = <MemoryFirewall>[];
  for (final line in value.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final firewallParts = trimmed.split('|');
    final identity = firewallParts.first.trim();
    final grants = _decodeFirewallGrantSegments(firewallParts.skip(1));
    final equals = identity.indexOf('=');
    final rawId = equals < 0 ? identity : identity.substring(0, equals);
    final rawLabel = equals < 0 ? identity : identity.substring(equals + 1);
    final id = memoryFirewallIdFromLabel(rawId);
    if (id.isEmpty) {
      continue;
    }
    firewalls.add(
      MemoryFirewall(
        id: id,
        label: rawLabel.trim(),
        shares: grants.readers,
        writers: grants.writers,
      ),
    );
  }
  return normalizeMemoryFirewalls(firewalls);
}

/// Decodes read and write principal segments from one firewall settings line.
_MemoryFirewallGrantSegments _decodeFirewallGrantSegments(
  Iterable<String> segments,
) {
  final readers = <MemoryFirewallShare>[];
  final writers = <MemoryFirewallShare>[];
  for (final segment in segments) {
    final classified = _classifyFirewallGrantSegment(segment);
    final principals = _settingsCommaValues(
      classified.values,
    ).map(memoryFirewallShareFromText);
    if (classified.kind == _MemoryFirewallGrantKind.write) {
      writers.addAll(principals);
    } else {
      readers.addAll(principals);
    }
  }
  return _MemoryFirewallGrantSegments(readers: readers, writers: writers);
}

/// Classifies one optional grant segment as read or write grants.
_MemoryFirewallGrantSegment _classifyFirewallGrantSegment(String segment) {
  final trimmed = segment.trim();
  final colon = trimmed.indexOf(':');
  if (colon <= 0) {
    return _MemoryFirewallGrantSegment(
      kind: _MemoryFirewallGrantKind.read,
      values: trimmed,
    );
  }
  final prefix = trimmed.substring(0, colon).trim().toLowerCase();
  final values = trimmed.substring(colon + 1).trim();
  if (prefix == 'write' || prefix == 'writers') {
    return _MemoryFirewallGrantSegment(
      kind: _MemoryFirewallGrantKind.write,
      values: values,
    );
  }
  if (prefix == 'read' || prefix == 'reader' || prefix == 'readers') {
    return _MemoryFirewallGrantSegment(
      kind: _MemoryFirewallGrantKind.read,
      values: values,
    );
  }
  return _MemoryFirewallGrantSegment(
    kind: _MemoryFirewallGrantKind.read,
    values: trimmed,
  );
}

/// Encodes one memory firewall share as editable kind:id=Label text.
String _encodeMemoryFirewallShare(MemoryFirewallShare share) {
  return '${share.kind}:${share.id}=${share.label}';
}

/// Parses comma-separated settings values.
List<String> _settingsCommaValues(String value) {
  return value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

/// _MemoryFirewallGrantKind names editable firewall grant roles.
enum _MemoryFirewallGrantKind { read, write }

/// _MemoryFirewallGrantSegment stores one parsed settings grant segment.
class _MemoryFirewallGrantSegment {
  /// Creates a classified settings segment.
  const _MemoryFirewallGrantSegment({required this.kind, required this.values});

  /// Whether this segment grants read or write.
  final _MemoryFirewallGrantKind kind;

  /// Comma-separated principal text.
  final String values;
}

/// _MemoryFirewallGrantSegments stores decoded read and write grant principals.
class _MemoryFirewallGrantSegments {
  /// Creates decoded grant principals.
  const _MemoryFirewallGrantSegments({
    required this.readers,
    required this.writers,
  });

  /// Read principals.
  final List<MemoryFirewallShare> readers;

  /// Write principals.
  final List<MemoryFirewallShare> writers;
}
