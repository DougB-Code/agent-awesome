/// Config file collection and text editor widgets.
part of 'settings_panel.dart';

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
