/// Settings action rows and destructive confirmation helpers.
part of 'settings_panel.dart';

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({required this.children});

  final List<Widget> children;

  /// Builds settings action buttons with standard spacing.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: children),
    );
  }
}

/// Confirms a destructive settings deletion.
Future<bool> _confirmSettingsDelete(
  BuildContext context, {
  required String label,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete configuration'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
