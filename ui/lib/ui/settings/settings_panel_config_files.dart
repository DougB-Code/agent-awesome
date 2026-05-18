/// Config file text editor widgets.
part of 'settings_panel.dart';

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
