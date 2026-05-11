/// Backlog task creation dialog.
part of 'backlog_section.dart';

/// Shows the context creation dialog.
Future<void> _showTaskCreateDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskCreateDialog(controller: controller);
    },
  );
}

class _TaskCreateDialog extends StatefulWidget {
  const _TaskCreateDialog({required this.controller});

  final AgentAwesomeAppController controller;

  @override
  State<_TaskCreateDialog> createState() => _TaskCreateDialogState();
}

class _TaskCreateDialogState extends State<_TaskCreateDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _topics = TextEditingController();
  String _priority = 'normal';
  bool _linkMemory = false;

  /// Cleans up dialog controllers.
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _topics.dispose();
    super.dispose();
  }

  /// Builds the context creation dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Backlog Item'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TaskTextField(controller: _title, label: 'Title'),
            const SizedBox(height: 10),
            _TaskTextField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _TaskDropdown(
              value: _priority,
              values: _taskPriorities,
              tooltip: 'Priority',
              onChanged: (value) => setState(() => _priority = value),
            ),
            const SizedBox(height: 10),
            _TaskTextField(controller: _topics, label: 'Topics'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Link selected memory'),
              value: _linkMemory,
              onChanged: widget.controller.selectedMemory == null
                  ? null
                  : (value) => setState(() => _linkMemory = value ?? false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }

  /// Creates the dialog backlog item.
  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      return;
    }
    await widget.controller.createTaskFromUi(
      title,
      description: _description.text.trim(),
      priority: _priority,
      topics: splitCommaSeparatedValues(_topics.text),
      linkSelectedMemory: _linkMemory,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
