/// Settings local exec command editing dialog.
part of 'settings_panel.dart';

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
