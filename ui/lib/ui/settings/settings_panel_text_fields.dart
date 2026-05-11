/// Settings inline, read-only, and autosave text fields.
part of 'settings_panel.dart';

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
