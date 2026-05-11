/// Runtime profile collection and profile editor widgets.
part of 'settings_panel.dart';

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
