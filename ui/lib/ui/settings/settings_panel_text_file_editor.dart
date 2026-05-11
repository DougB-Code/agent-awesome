/// Settings raw text-file editor widget.
part of 'settings_panel.dart';

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
