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

  /// Creates state for inline settings edits.
  @override
  State<_SettingsInlineField> createState() => _SettingsInlineFieldState();
}

class _SettingsInlineFieldState extends State<_SettingsInlineField> {
  static const Duration _saveDelay = Duration(milliseconds: 500);

  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.value;
  Timer? _saveTimer;

  /// Initializes focus tracking for autosave flushes.
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
    _saveTimer?.cancel();
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
        onChanged: (_) => _scheduleSave(),
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Flushes changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _save();
    }
  }

  /// Emits the new value when it differs from the saved value.
  void _save() {
    _saveTimer?.cancel();
    final next = _controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    widget.onChanged(next);
  }

  /// Schedules one save after a short edit pause.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
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
  static const Duration _saveDelay = Duration(milliseconds: 500);

  late final FocusNode _focusNode = FocusNode();
  late String _savedValue = widget.initialSavedValue;
  Timer? _saveTimer;

  /// Initializes focus tracking for autosave flushes.
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
    _saveTimer?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// Builds an editable field that saves after each edit pause.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        focusNode: _focusNode,
        controller: widget.controller,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        onChanged: (_) => _scheduleSave(),
        onFieldSubmitted: (_) => _save(),
        decoration: SettingsInputDecoration.field(context, label: widget.label),
      ),
    );
  }

  /// Flushes changed field content after focus leaves the field.
  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      return;
    }
    _save();
  }

  /// Saves changed field content immediately.
  void _save() {
    _saveTimer?.cancel();
    final next = widget.controller.text.trim();
    if (next == _savedValue.trim()) {
      return;
    }
    _savedValue = next;
    unawaited(widget.onSave(next));
  }

  /// Schedules one save after a short edit pause.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
  }
}
