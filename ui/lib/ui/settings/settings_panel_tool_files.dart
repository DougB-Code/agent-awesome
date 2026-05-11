/// Settings tool configuration file card and dropdown widgets.
part of 'settings_panel.dart';

class _SettingsToolFileCard extends StatelessWidget {
  const _SettingsToolFileCard({
    required this.entry,
    required this.entries,
    required this.onSelected,
    required this.onAssign,
    required this.onCreate,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ConfigFileEntry entry;
  final List<ConfigFileEntry> entries;
  final ValueChanged<ConfigFileEntry> onSelected;
  final VoidCallback? onAssign;
  final VoidCallback onCreate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Builds file selection and profile assignment controls.
  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      title: 'Tool config file',
      children: <Widget>[
        _SettingsToolConfigDropdown(
          label: 'Config',
          entries: entries,
          selectedPath: entry.path,
          onChanged: onSelected,
        ),
        _SettingsReadOnlyField(label: 'Path', value: entry.path),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton(
              onPressed: onAssign,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      entry.assigned ? 'Assigned' : 'Use for profile',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCreate,
              tooltip: 'Add tool config',
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: onDuplicate,
              tooltip: 'Duplicate tool config',
              icon: const Icon(Icons.content_copy),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete tool config',
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsToolConfigDropdown extends StatelessWidget {
  const _SettingsToolConfigDropdown({
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onChanged,
  });

  final String label;
  final List<ConfigFileEntry> entries;
  final String selectedPath;
  final ValueChanged<ConfigFileEntry> onChanged;

  /// Builds a filename-based selector for tool config files.
  @override
  Widget build(BuildContext context) {
    final selected = entries.any((entry) => entry.path == selectedPath)
        ? selectedPath
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final entry in entries)
            DropdownMenuItem<String>(
              value: entry.path,
              child: Text(entry.fileLabel, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (path) {
          if (path == null) {
            return;
          }
          for (final entry in entries) {
            if (entry.path == path) {
              onChanged(entry);
              return;
            }
          }
        },
        decoration: SettingsInputDecoration.field(context, label: label),
      ),
    );
  }
}
