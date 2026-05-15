/// Backlog task metadata editing dialog.
part of 'backlog_section.dart';

Future<void> _showTaskMetadataDialog(
  BuildContext context,
  AgentAwesomeAppController controller,
  WorkspaceTask task,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _TaskMetadataDialog(controller: controller, task: task);
    },
  );
}

class _TaskMetadataDialog extends StatefulWidget {
  const _TaskMetadataDialog({required this.controller, required this.task});

  final AgentAwesomeAppController controller;
  final WorkspaceTask task;

  @override
  State<_TaskMetadataDialog> createState() => _TaskMetadataDialogState();
}

class _TaskMetadataDialogState extends State<_TaskMetadataDialog> {
  final TextEditingController _estimate = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _urgency = TextEditingController();
  String _message = '';

  /// Initializes metadata fields from the selected backlog item.
  @override
  void initState() {
    super.initState();
    _estimate.text = widget.task.estimateMinutes <= 0
        ? ''
        : widget.task.estimateMinutes.toString();
    _location.text = widget.task.location;
    _owner.text = widget.task.owner;
    _urgency.text = _scoreInputText(widget.task.urgency);
  }

  /// Cleans up metadata field controllers.
  @override
  void dispose() {
    _estimate.dispose();
    _location.dispose();
    _owner.dispose();
    _urgency.dispose();
    super.dispose();
  }

  /// Builds the metadata editing dialog.
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Graph Metadata'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TaskTextField(
                controller: _estimate,
                label: 'Estimate minutes',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _TaskTextField(controller: _location, label: 'Location'),
              const SizedBox(height: 10),
              _TaskTextField(controller: _owner, label: 'Person'),
              const SizedBox(height: 10),
              _TaskTextField(
                controller: _urgency,
                label: 'Urgency 0-1',
                keyboardType: TextInputType.number,
              ),
              if (_message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: const TextStyle(color: AgentAwesomeColors.coral),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  /// Saves the edited metadata through graph-backed task tools.
  Future<void> _save() async {
    final estimateText = _estimate.text.trim();
    final estimate = estimateText.isEmpty ? 0 : int.tryParse(estimateText);
    if (estimate == null || estimate < 0) {
      setState(() => _message = 'Estimate must be zero or greater');
      return;
    }
    final urgency = _parseDialogScore(_urgency.text);
    if (urgency == null) {
      setState(() => _message = 'Scores must be between 0 and 1');
      return;
    }
    await widget.controller.updateTaskFromUi(
      taskId: widget.task.id,
      estimateMinutes: estimate,
      urgency: urgency,
      location: _location.text.trim(),
      owner: _owner.text.trim(),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
