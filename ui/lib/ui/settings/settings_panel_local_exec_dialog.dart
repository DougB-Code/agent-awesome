/// Settings local exec command editing dialog.
part of 'settings_panel.dart';

class _LocalExecFlagDialog extends StatefulWidget {
  const _LocalExecFlagDialog();

  /// Creates state for the add-flag dialog.
  @override
  State<_LocalExecFlagDialog> createState() => _LocalExecFlagDialogState();
}

class _LocalExecFlagDialogState extends State<_LocalExecFlagDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Builds the required-field CLI flag dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add flag'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: SettingsInputDecoration.field(context, label: 'Flag'),
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

  /// Returns the new flag when the required name is present.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      LocalExecCommandFlagConfig(
        name: name,
        description: _description.text.trim(),
      ),
    );
  }
}

class _LocalExecSubcommandDialog extends StatefulWidget {
  const _LocalExecSubcommandDialog();

  /// Creates state for the add-subcommand dialog.
  @override
  State<_LocalExecSubcommandDialog> createState() =>
      _LocalExecSubcommandDialogState();
}

class _LocalExecSubcommandDialogState
    extends State<_LocalExecSubcommandDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  /// Cleans up dialog field controllers.
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Builds the required-field CLI subcommand dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subcommand'),
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

  /// Returns the new subcommand when the required name is present.
  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      LocalExecSubcommandConfig(
        name: name,
        description: _description.text.trim(),
        flags: const <LocalExecCommandFlagConfig>[],
        subcommands: const <LocalExecSubcommandConfig>[],
      ),
    );
  }
}
